// État de l'assistante maternelle : cache mémoire + écriture vers le backend,
// et publication des vues partagées (planning, récapitulatifs) pour les parents.
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/engine.dart';
import '../domain/models.dart';
import 'backend.dart';

/// SMIC horaire brut de référence par défaut (modifiable dans l'app).
const kDefaultSmic = <int, double>{2024: 11.65, 2025: 11.88, 2026: 12.02};

class NannyStore extends ChangeNotifier {
  final NannyBackend backend;
  NannyStore(this.backend) {
    backend.onError = (e) {
      lastError = 'Échec de l\'enregistrement : $e';
      notifyListeners();
    };
  }

  bool loading = true;
  String? error; // erreur de chargement
  String? lastError; // erreur d'écriture à afficher (puis effacée)
  final Map<String, Child> children = {};
  final Map<String, Contract> contracts = {};
  final Map<String, DailyLog> logs = {};
  final Map<int, TaxScale> taxScales = {};
  final Map<int, double> incomeOverrides = {};
  final Map<String, LeavePeriod> leaves = {};
  final Map<String, MonthlySummary> locked = {};
  final Map<String, PaidLeaveEntry> paidLeaves = {};
  double netRatio = kDefaultNetRatio;

  /// Date d'arrêté des calculs (aujourd'hui) ; surchargeable pour les tests.
  DateTime Function() now = DateTime.now;

  CalcContext get ctx => CalcContext(leaves: leaves.values.toList(), asOf: now(), netRatio: netRatio);

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      _apply(await backend.loadAll());
    } catch (e) {
      error = '$e';
    }
    loading = false;
    notifyListeners();
  }

  void _apply(Data all) {
    Map<String, T> parse<T>(String c, T Function(Map<String, dynamic>) f) =>
        {for (final e in (all[c] ?? {}).entries) e.key: f(e.value)};
    children..clear()..addAll(parse(kChildren, Child.fromJson));
    contracts..clear()..addAll(parse(kContracts, Contract.fromJson));
    logs..clear()..addAll(parse(kLogs, DailyLog.fromJson));
    leaves..clear()..addAll(parse(kLeaves, LeavePeriod.fromJson));
    locked..clear()..addAll(parse(kLocked, MonthlySummary.fromJson));
    paidLeaves..clear()..addAll(parse(kPaidLeaves, PaidLeaveEntry.fromJson));
    taxScales.clear();
    kDefaultSmic.forEach((y, s) => taxScales[y] = TaxScale(y, s));
    for (final v in (all[kTaxScales] ?? {}).values) {
      final t = TaxScale.fromJson(v);
      taxScales[t.year] = t;
    }
    incomeOverrides.clear();
    final st = all[kSettings] ?? {};
    ((st['incomeOverrides']?['values'] ?? {}) as Map)
        .forEach((k, v) => incomeOverrides[int.parse('$k')] = (v as num).toDouble());
    netRatio = ((st['general']?['netRatio'] ?? kDefaultNetRatio) as num).toDouble();
  }

  void clearLastError() => lastError = null;

  // ---------- lecture ----------
  List<Child> get activeChildren =>
      children.values.where((c) => !c.archived).toList()..sort((a, b) => a.firstName.compareTo(b.firstName));
  List<Child> get archivedChildren => children.values.where((c) => c.archived).toList();

  List<Contract> contractsOf(String childId) =>
      contracts.values.where((c) => c.childId == childId).toList()..sort((a, b) => a.startDate.compareTo(b.startDate));

  Contract? contractOn(String childId, DateTime d) {
    for (final c in contractsOf(childId)) {
      if (c.isActiveOn(d)) return c;
    }
    return null;
  }

  /// Contrat existant chevauchant [c], le cas échéant.
  Contract? overlapping(Contract c) {
    for (final o in contractsOf(c.childId)) {
      if (contractsOverlap(c, o)) return o;
    }
    return null;
  }

  DailyLog? logOf(String childId, DateTime d) => logs['${childId}_${dateKey(d)}'];

  DayKind kindOf(String childId, DateTime d) => ctx.kindOf(childId, d);

  TaxScale scaleFor(int year) => taxScales[year] ?? TaxScale(year, kDefaultSmic[year] ?? kDefaultSmic.values.last);

  Map<String, DailyLog> _monthLogs(String childId, int year, int month) => {
        for (final d in daysOfMonth(year, month))
          if (logOf(childId, d) != null) dateKey(d): logOf(childId, d)!
      };

  /// Récapitulatif calculé (ou figé s'il a été validé).
  MonthlySummary? summary(String childId, int year, int month, {List<DayResult>? details, bool ignoreLock = false}) {
    final id = '${childId}_$year-${month.toString().padLeft(2, '0')}';
    if (!ignoreLock && details == null && locked[id] != null) return locked[id];
    final first = DateTime(year, month, 1), last = DateTime(year, month + 1, 0);
    final c0 = ctx;
    MonthlySummary? acc;
    for (final c in contractsOf(childId)) {
      if (c.startDate.isAfter(last) || (c.endDate != null && c.endDate!.isBefore(first))) continue;
      final s = computeMonth(c, year, month, _monthLogs(childId, year, month), ctx: c0, details: details);
      acc = acc == null ? s : acc + s;
    }
    return acc;
  }

  /// Simulation : le mois complet tel que prévu au planning (absences et
  /// retards déjà saisis compris).
  MonthlySummary? projectedSummary(String childId, int year, int month) {
    final first = DateTime(year, month, 1), last = DateTime(year, month + 1, 0);
    final c0 = ctx.projected();
    MonthlySummary? acc;
    for (final c in contractsOf(childId)) {
      if (c.startDate.isAfter(last) || (c.endDate != null && c.endDate!.isBefore(first))) continue;
      final s = computeMonth(c, year, month, _monthLogs(childId, year, month), ctx: c0);
      acc = acc == null ? s : acc + s;
    }
    return acc;
  }

  List<PaidLeaveEntry> paidLeavesOf(String contractId) =>
      paidLeaves.values.where((e) => e.contractId == contractId).toList()..sort((a, b) => a.date.compareTo(b.date));

  Future<void> savePaidLeave(PaidLeaveEntry e) async {
    paidLeaves[e.id] = e;
    _write([WriteOp(kPaidLeaves, e.id, e.toJson())]);
  }

  Future<void> deletePaidLeave(PaidLeaveEntry e) async {
    paidLeaves.remove(e.id);
    _write([WriteOp(kPaidLeaves, e.id, null)]);
  }

  /// Congés sur plusieurs jours pour un enfant : une période par plage continue.
  Future<void> addLeaveDays(String childId, List<DateTime> days, String label) async {
    final sorted = [...days.map(dayOnly)]..sort();
    final ops = <WriteOp>[];
    var i = 0;
    while (i < sorted.length) {
      var j = i;
      while (j + 1 < sorted.length && sorted[j + 1].difference(sorted[j]).inDays == 1) {
        j++;
      }
      final p = LeavePeriod(
          id: '${childId}_${dateKey(sorted[i])}_${DateTime.now().microsecondsSinceEpoch}',
          from: sorted[i],
          to: sorted[j],
          label: label,
          childIds: [childId]);
      leaves[p.id] = p;
      ops.add(WriteOp(kLeaves, p.id, p.toJson()));
      i = j + 1;
    }
    _write(ops);
    _publishMonths({for (final d in sorted) (childId, d.year, d.month)});
  }

  /// Retire les congés propres à un enfant sur ces jours (découpe les périodes).
  Future<void> removeLeaveDays(String childId, List<DateTime> days) async {
    final set = {for (final d in days) dateKey(d)};
    final ops = <WriteOp>[];
    for (final p in leaves.values.where((p) => p.childIds.length == 1 && p.childIds.first == childId).toList()) {
      final covered = <DateTime>[];
      for (var d = dayOnly(p.from); !d.isAfter(dayOnly(p.to)); d = addDays(d, 1)) {
        covered.add(d);
      }
      if (!covered.any((d) => set.contains(dateKey(d)))) continue;
      leaves.remove(p.id);
      ops.add(WriteOp(kLeaves, p.id, null));
      final keep = covered.where((d) => !set.contains(dateKey(d))).toList();
      if (keep.isNotEmpty) {
        _write(ops.toList());
        ops.clear();
        await addLeaveDays(childId, keep, p.label);
      }
    }
    if (ops.isNotEmpty) _write(ops);
    _publishMonths({for (final d in days) (childId, d.year, d.month)});
  }

  bool isLocked(String childId, int year, int month) =>
      locked.containsKey('${childId}_$year-${month.toString().padLeft(2, '0')}');

  AnnualTaxReport annualTax(int year) => computeAnnualTax(
        year: year,
        scale: scaleFor(year),
        contracts: contracts.values.toList(),
        logsById: logs,
        incomeOverride: incomeOverrides[year],
        ctx: ctx,
      );

  PaidLeaveEstimate? paidLeave(Contract c, int refEndYear) => computePaidLeave(c, refEndYear, logs, ctx: ctx);

  // ---------- écriture (non bloquante) ----------
  void _write(List<WriteOp> ops) {
    notifyListeners();
    backend.write(ops);
  }

  Future<void> saveChild(Child c) async {
    children[c.id] = c;
    _write([WriteOp(kChildren, c.id, c.toJson())]);
    await publishChild(c.id);
  }

  Future<void> saveContract(Contract c) async {
    contracts[c.id] = c;
    _write([WriteOp(kContracts, c.id, c.toJson())]);
    await publishChild(c.childId);
  }

  Future<void> deleteContract(Contract c) async {
    contracts.remove(c.id);
    _write([WriteOp(kContracts, c.id, null)]);
    await publishChild(c.childId);
  }

  Future<void> saveLogs(List<DailyLog> ls) async {
    for (final l in ls) {
      logs[l.id] = l;
    }
    _write([for (final l in ls) WriteOp(kLogs, l.id, l.toJson())]);
    _publishMonths({for (final l in ls) (l.childId, l.date.year, l.date.month)});
  }

  Future<void> saveLog(DailyLog l) => saveLogs([l]);

  Future<void> deleteLogs(List<DailyLog> ls) async {
    for (final l in ls) {
      logs.remove(l.id);
    }
    _write([for (final l in ls) WriteOp(kLogs, l.id, null)]);
    _publishMonths({for (final l in ls) (l.childId, l.date.year, l.date.month)});
  }

  Future<void> deleteLog(DailyLog l) => deleteLogs([l]);

  Future<void> saveLeave(LeavePeriod p) async {
    leaves[p.id] = p;
    _write([WriteOp(kLeaves, p.id, p.toJson())]);
    await publishAll();
  }

  Future<void> deleteLeave(LeavePeriod p) async {
    leaves.remove(p.id);
    _write([WriteOp(kLeaves, p.id, null)]);
    await publishAll();
  }

  Future<void> saveTaxScale(TaxScale t) async {
    taxScales[t.year] = t;
    _write([WriteOp(kTaxScales, '${t.year}', t.toJson())]);
  }

  Future<void> setNetRatio(double r) async {
    netRatio = r;
    _write([WriteOp(kSettings, 'general', {'netRatio': r})]);
    await publishAll();
  }

  Future<void> setIncomeOverride(int year, double? v) async {
    if (v == null) {
      incomeOverrides.remove(year);
    } else {
      incomeOverrides[year] = v;
    }
    _write([
      WriteOp(kSettings, 'incomeOverrides', {
        'values': {for (final e in incomeOverrides.entries) '${e.key}': e.value}
      })
    ]);
  }

  /// Valide et fige un mois : un avenant ou un pointage ultérieur ne le
  /// modifie plus (déverrouillable).
  Future<void> lockMonth(String childId, int year, int month) async {
    final s = summary(childId, year, month, ignoreLock: true);
    if (s == null) return;
    final l = s.asLocked();
    locked[l.id] = l;
    _write([WriteOp(kLocked, l.id, l.toJson())]);
    _publishMonths({(childId, year, month)});
  }

  Future<void> unlockMonth(String childId, int year, int month) async {
    final id = '${childId}_$year-${month.toString().padLeft(2, '0')}';
    locked.remove(id);
    _write([WriteOp(kLocked, id, null)]);
    _publishMonths({(childId, year, month)});
  }

  // ---------- export / import ----------
  Data snapshot() => {
        kChildren: {for (final e in children.entries) e.key: e.value.toJson()},
        kContracts: {for (final e in contracts.entries) e.key: e.value.toJson()},
        kLogs: {for (final e in logs.entries) e.key: e.value.toJson()},
        kLeaves: {for (final e in leaves.entries) e.key: e.value.toJson()},
        kLocked: {for (final e in locked.entries) e.key: e.value.toJson()},
        kPaidLeaves: {for (final e in paidLeaves.entries) e.key: e.value.toJson()},
        kTaxScales: {for (final e in taxScales.entries) '${e.key}': e.value.toJson()},
        kSettings: {
          'general': {'netRatio': netRatio},
          'incomeOverrides': {
            'values': {for (final e in incomeOverrides.entries) '${e.key}': e.value}
          },
        },
      };

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
        'app': 'ASSMATIA',
        'exportedAt': DateTime.now().toIso8601String(),
        'data': snapshot(),
      });

  /// Fusionne des données (export ou mode local) dans le compte courant.
  Future<void> importData(Data d) async {
    final ops = <WriteOp>[
      for (final c in kPrivateCollections)
        for (final e in (d[c] ?? {}).entries) WriteOp(c, e.key, Map<String, dynamic>.from(e.value)..remove('nannyId')),
    ];
    final merged = snapshot();
    for (final op in ops) {
      (merged[op.collection] ??= {})[op.id] = op.data!;
    }
    _apply(merged);
    _write(ops);
    await publishAll();
  }

  /// Supprime toutes les données de l'assistante maternelle (suppression de compte).
  Future<void> deleteEverything() async {
    final ops = <WriteOp>[];
    for (final c in [...kPrivateCollections, kSharedPlannings, kSummaries]) {
      for (final id in await backend.idsWhere(c, 'nannyId', _nannyIdOrEmpty)) {
        ops.add(WriteOp(c, id, null));
      }
    }
    backend.write(ops);
    _apply({});
    notifyListeners();
  }

  String get _nannyIdOrEmpty => backend is FirestoreNannyBackend ? (backend as FirestoreNannyBackend).nannyId : '';

  // ---------- publication vers les parents ----------
  Future<void> publishAll() async {
    for (final id in children.keys) {
      await publishChild(id);
    }
  }

  /// Republie le planning et TOUS les récapitulatifs de l'enfant (de son
  /// premier contrat au mois prochain) avec la liste d'accès à jour, et
  /// supprime les récapitulatifs devenus sans objet. Retirer un parent lui
  /// retire donc l'accès à tout l'historique.
  Future<void> publishChild(String childId) async {
    if (!backend.supportsSharing) return;
    final child = children[childId];
    if (child == null) return;
    final today = now();
    final cs = contractsOf(childId);
    final current = contractOn(childId, today) ?? (cs.isEmpty ? null : cs.last);
    final terms = current == null ? null : resolveTerms(current, today);
    final ops = <WriteOp>[
      WriteOp(kSharedPlannings, childId, {
        'childId': childId,
        'firstName': child.firstName,
        'color': child.color,
        'parentEmails': child.parentEmails,
        'schedule': terms?.schedule.toJson(),
        'weeklyHours': terms?.weeklyHours ?? 0,
        'updatedAt': today.toIso8601String(),
      }),
    ];
    final keep = <String>{};
    if (cs.isNotEmpty) {
      var m = DateTime(cs.first.startDate.year, cs.first.startDate.month);
      final stop = DateTime(today.year, today.month + 1);
      while (!m.isAfter(stop)) {
        final op = _summaryOp(child, m.year, m.month);
        if (op.data != null) {
          ops.add(op);
          keep.add(op.id);
        }
        m = DateTime(m.year, m.month + 1);
      }
    }
    try {
      for (final id in await backend.idsWhere(kSummaries, 'childId', childId)) {
        if (!keep.contains(id)) ops.add(WriteOp(kSummaries, id, null));
      }
    } catch (_) {/* hors ligne : nettoyage au prochain passage */}
    backend.write(ops);
  }

  void _publishMonths(Set<(String, int, int)> months) {
    if (!backend.supportsSharing) return;
    final ops = <WriteOp>[];
    for (final (childId, y, m) in months) {
      final child = children[childId];
      if (child != null) ops.add(_summaryOp(child, y, m));
    }
    if (ops.isNotEmpty) backend.write(ops);
  }

  WriteOp _summaryOp(Child child, int year, int month) {
    final s = summary(child.id, year, month);
    final id = '${child.id}_$year-${month.toString().padLeft(2, '0')}';
    if (s == null) return WriteOp(kSummaries, id, null);
    return WriteOp(kSummaries, id, {
      ...s.toJson(),
      'firstName': child.firstName,
      'parentEmails': child.parentEmails,
    });
  }
}
