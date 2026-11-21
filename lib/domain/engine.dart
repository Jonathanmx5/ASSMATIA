// Moteur de calcul : résolution des avenants, mensualisation, indemnités,
// déduction d'absence (méthode Cour de cassation) et abattement fiscal.
import 'models.dart';

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

/// Résultat journalier (présence effective et indemnités).
class DayResult {
  final DateTime date;
  final double plannedHours;
  final double workedHours;
  final double absenceDeductedHours;
  final double meal;
  final double maintenance;
  const DayResult(this.date, this.plannedHours, this.workedHours,
      this.absenceDeductedHours, this.meal, this.maintenance);
}

DayResult computeDay(ContractTerms t, DateTime d, DailyLog? log) {
  final planned = t.schedule.hoursFor(d.weekday);
  double worked;
  double absence = 0;
  switch (log?.status) {
    case null:
      worked = planned;
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
        (byHour > t.allowances.maintenancePerDay
            ? byHour
            : t.allowances.maintenancePerDay);
  }
  return DayResult(d, planned, worked, absence, meal, maint);
}

/// Montant à déduire (Cour de cassation), arrondi au centime.
double cassationDeduction(
    double monthlySalary, double absenceHours, double potentialHours) {
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
  final double baseSalary; // mensualisation (proratisée si besoin)
  final double absenceDeduction;
  final double netSalary; // salaire - déductions (base imposable)
  final double plannedHours;
  final double workedHours;
  final double absenceHours;
  final int daysPresent;
  final double meals;
  final double maintenance;
  final double hourlyRate; // taux actif en fin de mois
  const MonthlySummary({
    required this.childId,
    required this.year,
    required this.month,
    required this.baseSalary,
    required this.absenceDeduction,
    required this.netSalary,
    required this.plannedHours,
    required this.workedHours,
    required this.absenceHours,
    required this.daysPresent,
    required this.meals,
    required this.maintenance,
    required this.hourlyRate,
  });

  double get allowancesTotal => round2(meals + maintenance);
  double get totalToPay => round2(netSalary + meals + maintenance);

  String get id => '${childId}_$year-${month.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'childId': childId,
        'year': year,
        'month': month,
        'baseSalary': baseSalary,
        'absenceDeduction': absenceDeduction,
        'netSalary': netSalary,
        'plannedHours': plannedHours,
        'workedHours': workedHours,
        'absenceHours': absenceHours,
        'daysPresent': daysPresent,
        'meals': meals,
        'maintenance': maintenance,
        'hourlyRate': hourlyRate,
      };
  factory MonthlySummary.fromJson(Map<String, dynamic> j) {
    double d(String k) => ((j[k] ?? 0) as num).toDouble();
    return MonthlySummary(
      childId: j['childId'] as String,
      year: (j['year'] as num).toInt(),
      month: (j['month'] as num).toInt(),
      baseSalary: d('baseSalary'),
      absenceDeduction: d('absenceDeduction'),
      netSalary: d('netSalary'),
      plannedHours: d('plannedHours'),
      workedHours: d('workedHours'),
      absenceHours: d('absenceHours'),
      daysPresent: ((j['daysPresent'] ?? 0) as num).toInt(),
      meals: d('meals'),
      maintenance: d('maintenance'),
      hourlyRate: d('hourlyRate'),
    );
  }
}

/// Récapitulatif mensuel d'un contrat.
///
/// Salaire : pour chaque jour actif d, contribution =
///   mensualisation(T_d) × heures prévues(d) / heures potentielles du mois(T_d).
/// Sur un mois complet sans avenant, cela vaut exactement la mensualisation ;
/// en cas d'entrée/sortie ou d'avenant en cours de mois, cela proratise.
/// [logs] : suivis du mois indexés par dateKey.
MonthlySummary computeMonth(
    Contract c, int year, int month, Map<String, DailyLog> logs) {
  double salary = 0, deduction = 0, planned = 0, worked = 0, absence = 0;
  double meals = 0, maint = 0;
  int present = 0;
  final potentialCache = <WeeklySchedule, double>{};
  ContractTerms? last;
  for (final d in daysOfMonth(year, month)) {
    if (!c.isActiveOn(d)) continue;
    final t = resolveTerms(c, d);
    last = t;
    final pot = potentialCache.putIfAbsent(
        t.schedule, () => potentialHoursOfMonth(t.schedule, year, month));
    final r = computeDay(t, d, logs[dateKey(d)]);
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
  return MonthlySummary(
    childId: c.childId,
    year: year,
    month: month,
    baseSalary: base,
    absenceDeduction: ded,
    netSalary: round2(base - ded),
    plannedHours: round2(planned),
    workedHours: round2(worked),
    absenceHours: round2(absence),
    daysPresent: present,
    meals: round2(meals),
    maintenance: round2(maint),
    hourlyRate: last?.hourlyRate ?? 0,
  );
}

/// Abattement journalier : 3 × SMIC si >= 8 h, sinon (h/8) × 3 × SMIC.
double dailyAllowanceDeduction(double hours, double smic) {
  if (hours <= 0) return 0;
  final full = 3 * smic;
  return hours >= 8 ? full : hours / 8 * full;
}

class AnnualTaxReport {
  final int year;
  final double smic;
  final int careDays; // journées d'accueil (tous enfants)
  final double totalAbatement;
  final double taxableIncome; // revenus imposables (hors indemnités)
  final double netTaxable;
  final Map<String, double> abatementByChild;
  final Map<String, double> incomeByChild;
  const AnnualTaxReport({
    required this.year,
    required this.smic,
    required this.careDays,
    required this.totalAbatement,
    required this.taxableIncome,
    required this.netTaxable,
    required this.abatementByChild,
    required this.incomeByChild,
  });
}

/// Bilan fiscal sur l'année civile, tous enfants confondus.
/// [incomeOverride] : revenus imposables saisis manuellement (sinon somme
/// des salaires nets calculés, hors indemnités).
AnnualTaxReport computeAnnualTax({
  required int year,
  required TaxScale scale,
  required List<Contract> contracts,
  required Map<String, DailyLog> logsById, // clé DailyLog.id
  double? incomeOverride,
}) {
  double totalAbat = 0, income = 0;
  int days = 0;
  final abByChild = <String, double>{};
  final incByChild = <String, double>{};
  for (final c in contracts) {
    for (var m = 1; m <= 12; m++) {
      final monthLogs = <String, DailyLog>{};
      for (final d in daysOfMonth(year, m)) {
        if (!c.isActiveOn(d)) continue;
        final log = logsById['${c.childId}_${dateKey(d)}'];
        if (log != null) monthLogs[dateKey(d)] = log;
        final r = computeDay(resolveTerms(c, d), d, log);
        if (r.workedHours > 0) {
          final a = dailyAllowanceDeduction(r.workedHours, scale.smicHourly);
          totalAbat += a;
          abByChild[c.childId] = (abByChild[c.childId] ?? 0) + a;
          days++;
        }
      }
      final s = computeMonth(c, year, m, monthLogs);
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
    netTaxable: round2(inc - abat < 0 ? 0 : inc - abat),
    abatementByChild: abByChild.map((k, v) => MapEntry(k, round2(v))),
    incomeByChild: incByChild.map((k, v) => MapEntry(k, round2(v))),
  );
}
