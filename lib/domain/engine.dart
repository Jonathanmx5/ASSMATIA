// Moteur de calcul : résolution des avenants, mensualisation, indemnités,
// déduction d'absence (méthode Cour de cassation), congés payés et
// abattement fiscal.
import 'dart:math' as math;

import 'models.dart';

/// Taux de conversion brut → net par défaut (cotisations salariales ≈ 22 %).
const kDefaultNetRatio = 0.78;

/// Résout l'état actif du contrat à la date [d] : contrat initial complété
/// par les avenants dont effectiveFrom <= d, triés chronologiquement.
ContractTerms resolveTerms(Contract c, DateTime d) {
  final day = dayOnly(d);
  final sorted = [...c.amendments]
    ..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
  var t = c.base;
  for (final a in sorted) {
    if (!dayOnly(a.effectiveFrom).isAfter(day)) t = t.apply(a);
  }
  return t;
}

Iterable<DateTime> daysOfMonth(int year, int month) sync* {
  final n = DateTime(year, month + 1, 0).day;
  for (var i = 1; i <= n; i++) {
    yield DateTime(year, month, i);
  }
}

/// Nature d'une journée sans pointage.
enum DayKind {
  /// Jour d'accueil prévu, passé : compté comme effectué selon planning.
  normal,
  /// Jour férié : payé (mensualisation) mais sans accueil.
  publicHoliday,
  /// Congés / semaine non programmée : sans accueil ni déduction.
  leave,
  /// Jour futur : prévisionnel, pas encore effectué.
  future,
}

/// Contexte du calcul : jours fériés, périodes sans accueil et date d'arrêté.
class CalcContext {
  final List<LeavePeriod> leaves;
  final DateTime? asOf; // null = tout est considéré comme passé
  final bool holidaysOff;
  final double netRatio;
  final Map<int, Set<String>> _holidayCache = {};
  CalcContext({this.leaves = const [], this.asOf, this.holidaysOff = true, this.netRatio = kDefaultNetRatio});

  DayKind kindOf(String childId, DateTime d) {
    if (leaves.any((l) => l.covers(childId, d))) return DayKind.leave;
    if (holidaysOff &&
        _holidayCache.putIfAbsent(d.year, () => frenchPublicHolidays(d.year)).contains(dateKey(d))) {
      return DayKind.publicHoliday;
    }
    if (asOf != null && dayOnly(d).isAfter(dayOnly(asOf!))) return DayKind.future;
    return DayKind.normal;
  }
}

/// Résultat journalier (présence effective et indemnités).
class DayResult {
  final DateTime date;
  final DayKind kind;
  final double plannedHours;
  final double workedHours;
  final double absenceDeductedHours;
  final double meal;
  final double maintenance;
  const DayResult(this.date, this.plannedHours, this.workedHours,
      this.absenceDeductedHours, this.meal, this.maintenance, {this.kind = DayKind.normal});
}

/// Un pointage explicite prime toujours sur la nature du jour.
DayResult computeDay(ContractTerms t, DateTime d, DailyLog? log, {DayKind kind = DayKind.normal}) {
  final planned = t.schedule.hoursFor(d.weekday);
  double worked;
  double absence = 0;
  switch (log?.status) {
    case null:
      worked = kind == DayKind.normal ? planned : 0;
    case DayStatus.present:
      worked = log!.actualSlots == null
          ? planned
          : log.actualSlots!.fold(0.0, (a, s) => a + s.hours);
    case DayStatus.absentDeducted:
      worked = 0;
      absence = log!.absenceHours > 0 ? log.absenceHours : planned;
    case DayStatus.absentNotDeducted:
    case DayStatus.notScheduled:
      worked = 0;
  }
  double meal = 0, maint = 0;
  if (worked > 0) {
    meal = log?.mealOverride ?? t.allowances.mealPerDay;
    final byHour = t.allowances.maintenancePerHour * worked;
    maint = log?.maintenanceOverride ??
        (byHour > t.allowances.maintenancePerDay ? byHour : t.allowances.maintenancePerDay);
  }
  return DayResult(d, planned, worked, absence, meal, maint, kind: kind);
}

/// Montant à déduire (Cour de cassation), arrondi au centime.
double cassationDeduction(double monthlySalary, double absenceHours, double potentialHours) {
  if (potentialHours <= 0) return 0.0;
  return round2(monthlySalary * absenceHours / potentialHours);
}

/// Heures potentielles du mois selon un planning donné.
double potentialHoursOfMonth(WeeklySchedule s, int year, int month) =>
    daysOfMonth(year, month).fold(0.0, (a, d) => a + s.hoursFor(d.weekday));

class MonthlySummary {
  final String childId;
  final int year;
  final int month;
  final double baseSalary; // mensualisation brute (proratisée si besoin)
  final double absenceDeduction;
  final double grossSalary; // brut du mois = base - déductions
  final double netSalary; // net estimé = brut × taux de conversion
  final double plannedHours;
  final double workedHours;
  final double absenceHours;
  final double potentialHours; // heures potentielles du mois (Cour de cassation)
  final int daysPresent;
  final double meals;
  final double maintenance;
  final double hourlyRate;
  final bool provisional; // contient des jours futurs
  final bool locked; // mois validé et figé
  const MonthlySummary({
    required this.childId,
    required this.year,
    required this.month,
    required this.baseSalary,
    required this.absenceDeduction,
    required this.grossSalary,
    required this.netSalary,
    required this.plannedHours,
    required this.workedHours,
    required this.absenceHours,
    this.potentialHours = 0,
    required this.daysPresent,
    required this.meals,
    required this.maintenance,
    required this.hourlyRate,
    this.provisional = false,
    this.locked = false,
  });

  double get allowancesTotal => round2(meals + maintenance);
  double get totalToPay => round2(netSalary + meals + maintenance);

  String get id => '${childId}_$year-${month.toString().padLeft(2, '0')}';

  MonthlySummary asLocked() => MonthlySummary.fromJson({...toJson(), 'locked': true, 'provisional': false});

  MonthlySummary operator +(MonthlySummary b) => MonthlySummary(
        childId: childId,
        year: year,
        month: month,
        baseSalary: round2(baseSalary + b.baseSalary),
        absenceDeduction: round2(absenceDeduction + b.absenceDeduction),
        grossSalary: round2(grossSalary + b.grossSalary),
        netSalary: round2(netSalary + b.netSalary),
        plannedHours: round2(plannedHours + b.plannedHours),
        workedHours: round2(workedHours + b.workedHours),
        absenceHours: round2(absenceHours + b.absenceHours),
        potentialHours: math.max(potentialHours, b.potentialHours),
        daysPresent: daysPresent + b.daysPresent,
        meals: round2(meals + b.meals),
        maintenance: round2(maintenance + b.maintenance),
        hourlyRate: b.hourlyRate,
        provisional: provisional || b.provisional,
      );

  Map<String, dynamic> toJson() => {
        'childId': childId,
        'year': year,
        'month': month,
        'baseSalary': baseSalary,
        'absenceDeduction': absenceDeduction,
        'grossSalary': grossSalary,
        'netSalary': netSalary,
        'plannedHours': plannedHours,
        'workedHours': workedHours,
        'absenceHours': absenceHours,
        'potentialHours': potentialHours,
        'daysPresent': daysPresent,
        'meals': meals,
        'maintenance': maintenance,
        'hourlyRate': hourlyRate,
        'provisional': provisional,
        'locked': locked,
      };
  factory MonthlySummary.fromJson(Map<String, dynamic> j) {
    double d(String k) => ((j[k] ?? 0) as num).toDouble();
    return MonthlySummary(
      childId: j['childId'] as String,
      year: (j['year'] as num).toInt(),
      month: (j['month'] as num).toInt(),
      baseSalary: d('baseSalary'),
      absenceDeduction: d('absenceDeduction'),
      grossSalary: d('grossSalary'),
      netSalary: d('netSalary'),
      plannedHours: d('plannedHours'),
      workedHours: d('workedHours'),
      absenceHours: d('absenceHours'),
      potentialHours: d('potentialHours'),
      daysPresent: ((j['daysPresent'] ?? 0) as num).toInt(),
      meals: d('meals'),
      maintenance: d('maintenance'),
      hourlyRate: d('hourlyRate'),
      provisional: (j['provisional'] ?? false) as bool,
      locked: (j['locked'] ?? false) as bool,
    );
  }
}

/// Récapitulatif mensuel d'un contrat (et détail jour par jour).
///
/// Salaire : pour chaque jour actif d, contribution =
///   mensualisation(T_d) × heures prévues(d) / heures potentielles du mois(T_d).
/// Sur un mois complet sans avenant, cela vaut exactement la mensualisation ;
/// en cas d'entrée/sortie ou d'avenant en cours de mois, cela proratise.
/// Jours fériés et congés n'ont pas d'incidence sur le salaire mensualisé.
MonthlySummary computeMonth(Contract c, int year, int month, Map<String, DailyLog> logs,
    {CalcContext? ctx, List<DayResult>? details}) {
  ctx ??= CalcContext();
  double salary = 0, deduction = 0, planned = 0, worked = 0, absence = 0, potMax = 0;
  double meals = 0, maint = 0;
  int present = 0;
  var provisional = false;
  final potentialCache = <WeeklySchedule, double>{};
  ContractTerms? last;
  for (final d in daysOfMonth(year, month)) {
    if (!c.isActiveOn(d)) continue;
    final t = resolveTerms(c, d);
    last = t;
    final pot = potentialCache.putIfAbsent(t.schedule, () => potentialHoursOfMonth(t.schedule, year, month));
    potMax = math.max(potMax, pot);
    final kind = ctx.kindOf(c.childId, d);
    final log = logs[dateKey(d)];
    if (kind == DayKind.future && log == null && t.schedule.hoursFor(d.weekday) > 0) provisional = true;
    final r = computeDay(t, d, log, kind: kind);
    details?.add(r);
    if (pot > 0) {
      salary += t.monthlySalary * r.plannedHours / pot;
      deduction += t.monthlySalary * r.absenceDeductedHours / pot;
    }
    planned += r.plannedHours;
    worked += r.workedHours;
    absence += r.absenceDeductedHours;
    meals += r.meal;
    maint += r.maintenance;
    if (r.workedHours > 0) present++;
  }
  final base = round2(salary);
  final ded = round2(deduction);
  final gross = round2(base - ded);
  return MonthlySummary(
    childId: c.childId,
    year: year,
    month: month,
    baseSalary: base,
    absenceDeduction: ded,
    grossSalary: gross,
    netSalary: round2(gross * ctx.netRatio),
    plannedHours: round2(planned),
    workedHours: round2(worked),
    absenceHours: round2(absence),
    potentialHours: round2(potMax),
    daysPresent: present,
    meals: round2(meals),
    maintenance: round2(maint),
    hourlyRate: last?.hourlyRate ?? 0,
    provisional: provisional,
  );
}

// ---------------------------------------------------------------------------
// Congés payés (estimation) — période de référence du 1er juin au 31 mai.
// Acquisition : 2,5 jours ouvrables par mois d'accueil, plafond 30.
// Rémunération retenue : la plus favorable entre 10 % des salaires bruts de
// la période et le maintien de salaire (mensualisation / 26 par jour).
// ---------------------------------------------------------------------------
class PaidLeaveEstimate {
  final DateTime refStart;
  final DateTime refEnd;
  final int monthsWorked;
  final int daysAcquired;
  final double grossReference;
  final double tenPercent;
  final double maintien;
  final double retained;
  /// Année complète : CP déjà inclus dans la mensualisation (complément
  /// éventuel = retained - maintien). Année incomplète : à verser en plus.
  final bool includedInMonthly;
  const PaidLeaveEstimate({
    required this.refStart,
    required this.refEnd,
    required this.monthsWorked,
    required this.daysAcquired,
    required this.grossReference,
    required this.tenPercent,
    required this.maintien,
    required this.retained,
    required this.includedInMonthly,
  });
  double get toPayExtra => includedInMonthly ? round2(math.max(0, retained - maintien)) : retained;
}

/// [refEndYear] : année du 31 mai qui clôt la période de référence.
PaidLeaveEstimate? computePaidLeave(Contract c, int refEndYear, Map<String, DailyLog> logsById, {CalcContext? ctx}) {
  final start = DateTime(refEndYear - 1, 6, 1), end = DateTime(refEndYear, 5, 31);
  var months = 0;
  double gross = 0;
  for (var i = 0; i < 12; i++) {
    final m = DateTime(start.year, start.month + i, 1);
    final logs = <String, DailyLog>{};
    for (final d in daysOfMonth(m.year, m.month)) {
      final l = logsById['${c.childId}_${dateKey(d)}'];
      if (l != null) logs[dateKey(d)] = l;
    }
    final s = computeMonth(c, m.year, m.month, logs, ctx: ctx);
    if (s.plannedHours > 0) months++;
    gross += s.grossSalary;
  }
  if (months == 0) return null;
  final days = math.min(30, (months * 2.5).ceil());
  final refDay = c.endDate != null && c.endDate!.isBefore(end) ? c.endDate! : end;
  final t = resolveTerms(c, refDay);
  final ten = round2(gross * 0.10);
  final maintien = round2(t.monthlySalary / 26 * days);
  return PaidLeaveEstimate(
    refStart: start,
    refEnd: end,
    monthsWorked: months,
    daysAcquired: days,
    grossReference: round2(gross),
    tenPercent: ten,
    maintien: maintien,
    retained: math.max(ten, maintien),
    includedInMonthly: t.type == ContractType.fullYear,
  );
}

// ---------------------------------------------------------------------------
// Abattement fiscal annuel.
// ---------------------------------------------------------------------------

/// Abattement journalier : 3 × SMIC si >= 8 h, sinon (h/8) × 3 × SMIC.
double dailyAllowanceDeduction(double hours, double smic) {
  if (hours <= 0) return 0;
  final full = 3 * smic;
  return hours >= 8 ? full : hours / 8 * full;
}

class AnnualTaxReport {
  final int year;
  final double smic;
  final int careDays; // journées d'accueil effectives (tous enfants)
  final double totalAbatement;
  final double taxableIncome; // revenus imposables nets (hors indemnités)
  final double netTaxable;
  final Map<String, double> abatementByChild;
  final Map<String, double> incomeByChild;
  final bool partial; // année en cours : arrêté à la date du jour
  const AnnualTaxReport({
    required this.year,
    required this.smic,
    required this.careDays,
    required this.totalAbatement,
    required this.taxableIncome,
    required this.netTaxable,
    required this.abatementByChild,
    required this.incomeByChild,
    this.partial = false,
  });
}

/// Bilan fiscal sur l'année civile, tous enfants confondus. Seules les
/// journées d'accueil effectives (passées ou pointées, hors fériés et congés)
/// ouvrent droit à l'abattement. [incomeOverride] : revenus imposables saisis
/// (sinon somme des salaires nets estimés, hors indemnités).
AnnualTaxReport computeAnnualTax({
  required int year,
  required TaxScale scale,
  required List<Contract> contracts,
  required Map<String, DailyLog> logsById,
  double? incomeOverride,
  CalcContext? ctx,
}) {
  ctx ??= CalcContext();
  double totalAbat = 0, income = 0;
  int days = 0;
  final abByChild = <String, double>{};
  final incByChild = <String, double>{};
  for (final c in contracts) {
    for (var m = 1; m <= 12; m++) {
      final monthLogs = <String, DailyLog>{};
      for (final d in daysOfMonth(year, m)) {
        final l = logsById['${c.childId}_${dateKey(d)}'];
        if (l != null) monthLogs[dateKey(d)] = l;
      }
      final details = <DayResult>[];
      final s = computeMonth(c, year, m, monthLogs, ctx: ctx, details: details);
      for (final r in details) {
        if (r.workedHours > 0) {
          final a = dailyAllowanceDeduction(r.workedHours, scale.smicHourly);
          totalAbat += a;
          abByChild[c.childId] = (abByChild[c.childId] ?? 0) + a;
          days++;
        }
      }
      income += s.netSalary;
      incByChild[c.childId] = (incByChild[c.childId] ?? 0) + s.netSalary;
    }
  }
  final abat = round2(totalAbat);
  final inc = round2(incomeOverride ?? income);
  return AnnualTaxReport(
    year: year,
    smic: scale.smicHourly,
    careDays: days,
    totalAbatement: abat,
    taxableIncome: inc,
    netTaxable: round2(math.max(0, inc - abat)),
    abatementByChild: abByChild.map((k, v) => MapEntry(k, round2(v))),
    incomeByChild: incByChild.map((k, v) => MapEntry(k, round2(v))),
    partial: ctx.asOf != null && ctx.asOf!.isBefore(DateTime(year, 12, 31)),
  );
}
