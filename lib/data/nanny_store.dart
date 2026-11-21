// État de l'assistante maternelle : cache mémoire + écriture vers le backend,
// et publication des vues partagées (planning, récapitulatifs) pour les parents.
import 'package:flutter/foundation.dart';

import '../domain/engine.dart';
import '../domain/models.dart';
import 'backend.dart';

/// SMIC horaire brut de référence par défaut (modifiable dans l'app).
const kDefaultSmic = <int, double>{2024: 11.65, 2025: 11.88, 2026: 12.02};

class NannyStore extends ChangeNotifier {
  final NannyBackend backend;
  NannyStore(this.backend);

  bool loading = true;
  String? error;
  final Map<String, Child> children = {};
  final Map<String, Contract> contracts = {};
  final Map<String, DailyLog> logs = {};
  final Map<int, TaxScale> taxScales = {};
  final Map<int, double> incomeOverrides = {};

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final all = await backend.loadAll();
      children
        ..clear()
        ..addAll({
          for (final e in (all[kChildren] ?? {}).entries)
            e.key: Child.fromJson(e.value)
        });
      contracts
        ..clear()
        ..addAll({
          for (final e in (all[kContracts] ?? {}).entries)
            e.key: Contract.fromJson(e.value)
        });
      logs
        ..clear()
        ..addAll({
          for (final e in (all[kLogs] ?? {}).entries)
            e.key: DailyLog.fromJson(e.value)
        });
      taxScales.clear();
      kDefaultSmic.forEach((y, s) => taxScales[y] = TaxScale(y, s));
      for (final v in (all[kTaxScales] ?? {}).values) {
        final t = TaxScale.fromJson(v);
        taxScales[t.year] = t;
      }
      incomeOverrides.clear();
      final st = all[kSettings]?['incomeOverrides'];
      if (st != null) {
        (st['values'] as Map? ?? {}).forEach((k, v) =>
            incomeOverrides[int.parse('$k')] = (v as num).toDouble());
      }
    } catch (e) {
      error = '$e';
    }
    loading = false;
    notifyListeners();
  }

  // ---------- lecture ----------
  List<Child> get activeChildren =>
      children.values.where((c) => !c.archived).toList()
        ..sort((a, b) => a.firstName.compareTo(b.firstName));
  List<Child> get archivedChildren =>
      children.values.where((c) => c.archived).toList();

  List<Contract> contractsOf(String childId) =>
      contracts.values.where((c) => c.childId == childId).toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));

  Contract? contractOn(String childId, DateTime d) {
    for (final c in contractsOf(childId)) {
      if (c.isActiveOn(d)) return c;
    }
    return null;
  }

  DailyLog? logOf(String childId, DateTime d) =>
      logs['${childId}_${dateKey(d)}'];

  TaxScale scaleFor(int year) =>
      taxScales[year] ?? TaxScale(year, kDefaultSmic[year] ?? kDefaultSmic.values.last);

  MonthlySummary? summary(String childId, int year, int month) {
    final first = DateTime(year, month, 1);
    final last = DateTime(year, month + 1, 0);
    MonthlySummary? acc;
    for (final c in contractsOf(childId)) {
      if (c.startDate.isAfter(last) ||
          (c.endDate != null && c.endDate!.isBefore(first))) {
        continue;
      }
      final m = <String, DailyLog>{};
      for (final d in daysOfMonth(year, month)) {
        final l = logOf(childId, d);
        if (l != null) m[dateKey(d)] = l;
      }
      final s = computeMonth(c, year, month, m);
      acc = acc == null ? s : _add(acc, s);
    }
    return acc;
  }

  MonthlySummary _add(MonthlySummary a, MonthlySummary b) => MonthlySummary(
        childId: a.childId,
        year: a.year,
        month: a.month,
        baseSalary: round2(a.baseSalary + b.baseSalary),
        absenceDeduction: round2(a.absenceDeduction + b.absenceDeduction),
        netSalary: round2(a.netSalary + b.netSalary),
        plannedHours: round2(a.plannedHours + b.plannedHours),
        workedHours: round2(a.workedHours + b.workedHours),
        absenceHours: round2(a.absenceHours + b.absenceHours),
        daysPresent: a.daysPresent + b.daysPresent,
        meals: round2(a.meals + b.meals),
        maintenance: round2(a.maintenance + b.maintenance),
        hourlyRate: b.hourlyRate,
      );

  AnnualTaxReport annualTax(int year) => computeAnnualTax(
        year: year,
        scale: scaleFor(year),
        contracts: contracts.values.toList(),
        logsById: logs,
        incomeOverride: incomeOverrides[year],
      );

  // ---------- écriture ----------
  Future<void> saveChild(Child c) async {
    children[c.id] = c;
    notifyListeners();
    await backend.put(kChildren, c.id, c.toJson());
    await publishChild(c.id);
  }

  Future<void> saveContract(Contract c) async {
    contracts[c.id] = c;
    notifyListeners();
    await backend.put(kContracts, c.id, c.toJson());
    await publishChild(c.childId);
  }

  Future<void> deleteContract(Contract c) async {
    contracts.remove(c.id);
    notifyListeners();
    await backend.delete(kContracts, c.id);
    await publishChild(c.childId);
  }

  Future<void> saveLog(DailyLog l) async {
    logs[l.id] = l;
    notifyListeners();
    await backend.put(kLogs, l.id, l.toJson());
    await _publishSummary(l.childId, l.date.year, l.date.month);
  }

  Future<void> deleteLog(DailyLog l) async {
    logs.remove(l.id);
    notifyListeners();
    await backend.delete(kLogs, l.id);
    await _publishSummary(l.childId, l.date.year, l.date.month);
  }

  Future<void> saveTaxScale(TaxScale t) async {
    taxScales[t.year] = t;
    notifyListeners();
    await backend.put(kTaxScales, '${t.year}', t.toJson());
  }

  Future<void> setIncomeOverride(int year, double? v) async {
    if (v == null) {
      incomeOverrides.remove(year);
    } else {
      incomeOverrides[year] = v;
    }
    notifyListeners();
    await backend.put(kSettings, 'incomeOverrides', {
      'values': {for (final e in incomeOverrides.entries) '${e.key}': e.value}
    });
  }

  // ---------- publication vers les parents ----------
  Future<void> publishChild(String childId) async {
    if (!backend.supportsSharing) return;
    final child = children[childId];
    if (child == null) return;
    final now = DateTime.now();
    final current = contractOn(childId, now) ??
        (contractsOf(childId).isEmpty ? null : contractsOf(childId).last);
    final terms = current == null ? null : resolveTerms(current, now);
    await backend.put(kSharedPlannings, childId, {
      'childId': childId,
      'firstName': child.firstName,
      'color': child.color,
      'parentEmails': child.parentEmails,
      'schedule': terms?.schedule.toJson(),
      'weeklyHours': terms?.weeklyHours ?? 0,
      'updatedAt': now.toIso8601String(),
    });
    // Récapitulatifs : 12 derniers mois + mois courant.
    for (var i = 12; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      await _publishSummary(childId, d.year, d.month);
    }
  }

  Future<void> _publishSummary(String childId, int year, int month) async {
    if (!backend.supportsSharing) return;
    final child = children[childId];
    if (child == null) return;
    final s = summary(childId, year, month);
    final id = '${childId}_$year-${month.toString().padLeft(2, '0')}';
    if (s == null) {
      await backend.delete(kSummaries, id);
      return;
    }
    await backend.put(kSummaries, id, {
      ...s.toJson(),
      'firstName': child.firstName,
      'parentEmails': child.parentEmails,
    });
  }
}
