// Modèles du domaine (purs, sans dépendance Flutter/Firebase).

double round2(num x) => (x * 100).roundToDouble() / 100;

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDateKey(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

enum ContractType { fullYear, partialYear }

/// Tranche horaire en minutes depuis minuit.
class TimeSlot {
  final int startMin;
  final int endMin;
  const TimeSlot(this.startMin, this.endMin);
  double get hours => (endMin - startMin) / 60.0;

  static String fmt(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  @override
  String toString() => '${fmt(startMin)}-${fmt(endMin)}';

  Map<String, dynamic> toJson() => {'s': startMin, 'e': endMin};
  factory TimeSlot.fromJson(Map<String, dynamic> j) =>
      TimeSlot(j['s'] as int, j['e'] as int);
}

/// Planning hebdomadaire : weekday (1=lundi..7=dimanche) -> tranches.
class WeeklySchedule {
  final Map<int, List<TimeSlot>> days;
  const WeeklySchedule(this.days);

  List<TimeSlot> slotsFor(int weekday) => days[weekday] ?? const [];
  double hoursFor(int weekday) =>
      slotsFor(weekday).fold(0.0, (a, s) => a + s.hours);
  double get weeklyHours =>
      [for (var d = 1; d <= 7; d++) hoursFor(d)].fold(0.0, (a, b) => a + b);
  int get daysPerWeek =>
      [for (var d = 1; d <= 7; d++) hoursFor(d)].where((h) => h > 0).length;

  Map<String, dynamic> toJson() => {
        for (final e in days.entries)
          '${e.key}': e.value.map((s) => s.toJson()).toList()
      };
  factory WeeklySchedule.fromJson(Map<String, dynamic>? j) => WeeklySchedule({
        for (final e in (j ?? {}).entries)
          int.parse(e.key): (e.value as List)
              .map((x) => TimeSlot.fromJson(Map<String, dynamic>.from(x)))
              .toList()
      });
}

/// Indemnités : repas par jour d'accueil, entretien = max(forfait journalier,
/// taux horaire * heures du jour) — les deux montants sont saisis.
class Allowances {
  final double mealPerDay;
  final double maintenancePerDay;
  final double maintenancePerHour;
  /// Majoration (%) des heures au-delà de 45 h par semaine (fixée au contrat).
  final double overtimeMajorationPct;
  const Allowances(
      {this.mealPerDay = 0,
      this.maintenancePerDay = 0,
      this.maintenancePerHour = 0,
      this.overtimeMajorationPct = 10});

  Map<String, dynamic> toJson() => {
        'mealPerDay': mealPerDay,
        'maintenancePerDay': maintenancePerDay,
        'maintenancePerHour': maintenancePerHour,
        'overtimeMajorationPct': overtimeMajorationPct,
      };
  factory Allowances.fromJson(Map<String, dynamic>? j) => Allowances(
        mealPerDay: ((j?['mealPerDay']) ?? 0).toDouble(),
        maintenancePerDay: ((j?['maintenancePerDay']) ?? 0).toDouble(),
        maintenancePerHour: ((j?['maintenancePerHour']) ?? 0).toDouble(),
        overtimeMajorationPct: ((j?['overtimeMajorationPct']) ?? 10).toDouble(),
      );
}

/// Paramètres actifs d'un contrat à une date donnée.
class ContractTerms {
  final ContractType type;
  final double hourlyRate;
  final int weeksPerYear; // 52 en année complète
  final WeeklySchedule schedule;
  final Allowances allowances;
  const ContractTerms({
    required this.type,
    required this.hourlyRate,
    required this.weeksPerYear,
    required this.schedule,
    required this.allowances,
  });

  double get weeklyHours => schedule.weeklyHours;
  int get effectiveWeeks => type == ContractType.fullYear ? 52 : weeksPerYear;

  /// Heures mensualisées = heures hebdo × semaines / 12.
  double get monthlyHours => weeklyHours * effectiveWeeks / 12;

  /// Salaire mensualisé (arrondi au centime).
  double get monthlySalary => round2(hourlyRate * monthlyHours);

  ContractTerms apply(Amendment a) => ContractTerms(
        type: a.type ?? type,
        hourlyRate: a.hourlyRate ?? hourlyRate,
        weeksPerYear: a.weeksPerYear ?? weeksPerYear,
        schedule: a.schedule ?? schedule,
        allowances: a.allowances ?? allowances,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'hourlyRate': hourlyRate,
        'weeksPerYear': weeksPerYear,
        'schedule': schedule.toJson(),
        'allowances': allowances.toJson(),
      };
  factory ContractTerms.fromJson(Map<String, dynamic> j) => ContractTerms(
        type: ContractType.values.byName(j['type'] as String),
        hourlyRate: (j['hourlyRate'] as num).toDouble(),
        weeksPerYear: (j['weeksPerYear'] as num).toInt(),
        schedule: WeeklySchedule.fromJson(
            j['schedule'] == null ? null : Map<String, dynamic>.from(j['schedule'])),
        allowances: Allowances.fromJson(
            j['allowances'] == null ? null : Map<String, dynamic>.from(j['allowances'])),
      );
}

/// Avenant : modifie tout ou partie des paramètres à partir de effectiveFrom.
class Amendment {
  final String id;
  final DateTime effectiveFrom;
  final String note;
  final ContractType? type;
  final double? hourlyRate;
  final int? weeksPerYear;
  final WeeklySchedule? schedule;
  final Allowances? allowances;
  const Amendment({
    required this.id,
    required this.effectiveFrom,
    this.note = '',
    this.type,
    this.hourlyRate,
    this.weeksPerYear,
    this.schedule,
    this.allowances,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'effectiveFrom': dateKey(effectiveFrom),
        'note': note,
        if (type != null) 'type': type!.name,
        if (hourlyRate != null) 'hourlyRate': hourlyRate,
        if (weeksPerYear != null) 'weeksPerYear': weeksPerYear,
        if (schedule != null) 'schedule': schedule!.toJson(),
        if (allowances != null) 'allowances': allowances!.toJson(),
      };
  factory Amendment.fromJson(Map<String, dynamic> j) => Amendment(
        id: j['id'] as String,
        effectiveFrom: parseDateKey(j['effectiveFrom'] as String),
        note: (j['note'] ?? '') as String,
        type: j['type'] == null ? null : ContractType.values.byName(j['type']),
        hourlyRate: (j['hourlyRate'] as num?)?.toDouble(),
        weeksPerYear: (j['weeksPerYear'] as num?)?.toInt(),
        schedule: j['schedule'] == null
            ? null
            : WeeklySchedule.fromJson(Map<String, dynamic>.from(j['schedule'])),
        allowances: j['allowances'] == null
            ? null
            : Allowances.fromJson(Map<String, dynamic>.from(j['allowances'])),
      );
}

class Contract {
  final String id;
  final String childId;
  final DateTime startDate;
  final DateTime? endDate;
  final ContractTerms base;
  final List<Amendment> amendments;
  const Contract({
    required this.id,
    required this.childId,
    required this.startDate,
    this.endDate,
    required this.base,
    this.amendments = const [],
  });

  bool isActiveOn(DateTime d) {
    final x = dayOnly(d);
    return !x.isBefore(dayOnly(startDate)) &&
        (endDate == null || !x.isAfter(dayOnly(endDate!)));
  }

  Contract copyWith({DateTime? endDate, bool clearEnd = false, ContractTerms? base, List<Amendment>? amendments, DateTime? startDate}) =>
      Contract(
        id: id,
        childId: childId,
        startDate: startDate ?? this.startDate,
        endDate: clearEnd ? null : (endDate ?? this.endDate),
        base: base ?? this.base,
        amendments: amendments ?? this.amendments,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'childId': childId,
        'startDate': dateKey(startDate),
        'endDate': endDate == null ? null : dateKey(endDate!),
        'base': base.toJson(),
        'amendments': amendments.map((a) => a.toJson()).toList(),
      };
  factory Contract.fromJson(Map<String, dynamic> j) => Contract(
        id: j['id'] as String,
        childId: j['childId'] as String,
        startDate: parseDateKey(j['startDate'] as String),
        endDate: j['endDate'] == null ? null : parseDateKey(j['endDate']),
        base: ContractTerms.fromJson(Map<String, dynamic>.from(j['base'])),
        amendments: ((j['amendments'] ?? []) as List)
            .map((a) => Amendment.fromJson(Map<String, dynamic>.from(a)))
            .toList(),
      );
}

class Child {
  final String id;
  final String firstName;
  final int color; // ARGB
  final bool archived;
  final List<String> parentIds; // uid Firebase des parents rattachés
  final List<String> parentEmails; // invitations
  const Child({
    required this.id,
    required this.firstName,
    required this.color,
    this.archived = false,
    this.parentIds = const [],
    this.parentEmails = const [],
  });

  Child copyWith({String? firstName, int? color, bool? archived, List<String>? parentIds, List<String>? parentEmails}) => Child(
        id: id,
        firstName: firstName ?? this.firstName,
        color: color ?? this.color,
        archived: archived ?? this.archived,
        parentIds: parentIds ?? this.parentIds,
        parentEmails: parentEmails ?? this.parentEmails,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstName': firstName,
        'color': color,
        'archived': archived,
        'parentIds': parentIds,
        'parentEmails': parentEmails,
      };
  factory Child.fromJson(Map<String, dynamic> j) => Child(
        id: j['id'] as String,
        firstName: j['firstName'] as String,
        color: (j['color'] as num).toInt(),
        archived: (j['archived'] ?? false) as bool,
        parentIds: List<String>.from(j['parentIds'] ?? const []),
        parentEmails: List<String>.from(j['parentEmails'] ?? const []),
      );
}

enum DayStatus { present, absentDeducted, absentNotDeducted, notScheduled }

/// Suivi quotidien d'un enfant.
class DailyLog {
  final String childId;
  final DateTime date;
  final DayStatus status;
  final List<TimeSlot>? actualSlots; // null = planning théorique
  final double absenceHours; // heures d'absence (prévues au planning) à déduire
  final double extraHours; // heures en plus (retard des parents)
  final double? mealOverride; // indemnité repas saisie manuellement
  final double? maintenanceOverride;
  final String note;
  const DailyLog({
    required this.childId,
    required this.date,
    this.status = DayStatus.present,
    this.actualSlots,
    this.absenceHours = 0,
    this.extraHours = 0,
    this.mealOverride,
    this.maintenanceOverride,
    this.note = '',
  });

  String get id => '${childId}_${dateKey(date)}';

  Map<String, dynamic> toJson() => {
        'childId': childId,
        'date': dateKey(date),
        'status': status.name,
        'actualSlots': actualSlots?.map((s) => s.toJson()).toList(),
        'absenceHours': absenceHours,
        'extraHours': extraHours,
        'mealOverride': mealOverride,
        'maintenanceOverride': maintenanceOverride,
        'note': note,
      };
  factory DailyLog.fromJson(Map<String, dynamic> j) => DailyLog(
        childId: j['childId'] as String,
        date: parseDateKey(j['date'] as String),
        status: DayStatus.values.byName(j['status'] as String),
        actualSlots: (j['actualSlots'] as List?)
            ?.map((s) => TimeSlot.fromJson(Map<String, dynamic>.from(s)))
            .toList(),
        absenceHours: ((j['absenceHours'] ?? 0) as num).toDouble(),
        extraHours: ((j['extraHours'] ?? 0) as num).toDouble(),
        mealOverride: (j['mealOverride'] as num?)?.toDouble(),
        maintenanceOverride: (j['maintenanceOverride'] as num?)?.toDouble(),
        note: (j['note'] ?? '') as String,
      );
}

/// Barème fiscal annuel configurable.
class TaxScale {
  final int year;
  final double smicHourly;
  const TaxScale(this.year, this.smicHourly);
  Map<String, dynamic> toJson() => {'year': year, 'smicHourly': smicHourly};
  factory TaxScale.fromJson(Map<String, dynamic> j) =>
      TaxScale((j['year'] as num).toInt(), (j['smicHourly'] as num).toDouble());
}

/// Période sans accueil (congés de l'assistante maternelle, semaines non
/// programmées en année incomplète, fermeture…). childIds vide = tous.
class LeavePeriod {
  final String id;
  final DateTime from;
  final DateTime to;
  final String label;
  final List<String> childIds;
  const LeavePeriod({required this.id, required this.from, required this.to, this.label = '', this.childIds = const []});

  bool covers(String childId, DateTime d) {
    final x = dayOnly(d);
    return !x.isBefore(dayOnly(from)) && !x.isAfter(dayOnly(to)) &&
        (childIds.isEmpty || childIds.contains(childId));
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'from': dateKey(from), 'to': dateKey(to), 'label': label, 'childIds': childIds,
      };
  factory LeavePeriod.fromJson(Map<String, dynamic> j) => LeavePeriod(
        id: j['id'] as String,
        from: parseDateKey(j['from'] as String),
        to: parseDateKey(j['to'] as String),
        label: (j['label'] ?? '') as String,
        childIds: List<String>.from(j['childIds'] ?? const []),
      );
}

/// Jours fériés français (métropole) d'une année, en dateKey.
Set<String> frenchPublicHolidays(int y) {
  // Dimanche de Pâques (algorithme de Meeus/Jones/Butcher).
  final a = y % 19, b = y ~/ 100, c = y % 100, d = b ~/ 4, e = b % 4;
  final f = (b + 8) ~/ 25, g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4, k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = ((h + l - 7 * m + 114) % 31) + 1;
  final easter = DateTime(y, month, day);
  DateTime plus(int n) => DateTime(y, easter.month, easter.day + n);
  return {
    DateTime(y, 1, 1), plus(1), DateTime(y, 5, 1), DateTime(y, 5, 8), plus(39),
    plus(50), DateTime(y, 7, 14), DateTime(y, 8, 15), DateTime(y, 11, 1),
    DateTime(y, 11, 11), DateTime(y, 12, 25),
  }.map(dateKey).toSet();
}

/// Overlap checks.
bool slotsOverlap(List<TimeSlot> s) {
  final l = [...s]..sort((a, b) => a.startMin.compareTo(b.startMin));
  for (var i = 1; i < l.length; i++) {
    if (l[i].startMin < l[i - 1].endMin) return true;
  }
  return l.any((x) => x.endMin <= x.startMin);
}

bool contractsOverlap(Contract a, Contract b) {
  if (a.childId != b.childId || a.id == b.id) return false;
  final aEnd = a.endDate ?? DateTime(9999), bEnd = b.endDate ?? DateTime(9999);
  return !a.startDate.isAfter(bEnd) && !b.startDate.isAfter(aEnd);
}


/// Historique des congés payés d'un contrat : solde repris d'avant
/// l'application, jours pris et paiements effectués.
enum PaidLeaveKind { openingBalance, taken, payment }

class PaidLeaveEntry {
  final String id;
  final String contractId;
  final DateTime date;
  final PaidLeaveKind kind;
  final double days; // jours ouvrables (solde repris ou pris)
  final double amount; // montant brut versé (paiement / solde repris)
  final String note;
  const PaidLeaveEntry({
    required this.id,
    required this.contractId,
    required this.date,
    required this.kind,
    this.days = 0,
    this.amount = 0,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'contractId': contractId,
        'date': dateKey(date),
        'kind': kind.name,
        'days': days,
        'amount': amount,
        'note': note,
      };
  factory PaidLeaveEntry.fromJson(Map<String, dynamic> j) => PaidLeaveEntry(
        id: j['id'] as String,
        contractId: j['contractId'] as String,
        date: parseDateKey(j['date'] as String),
        kind: PaidLeaveKind.values.byName(j['kind'] as String),
        days: ((j['days'] ?? 0) as num).toDouble(),
        amount: ((j['amount'] ?? 0) as num).toDouble(),
        note: (j['note'] ?? '') as String,
      );
}

/// Solde des congés payés d'un contrat à partir de son historique.
class PaidLeaveLedger {
  final double openingDays;
  final double openingAmount;
  final double takenDays;
  final double paidAmount;
  const PaidLeaveLedger(this.openingDays, this.openingAmount, this.takenDays, this.paidAmount);
  factory PaidLeaveLedger.of(Iterable<PaidLeaveEntry> es) {
    double od = 0, oa = 0, td = 0, pa = 0;
    for (final e in es) {
      switch (e.kind) {
        case PaidLeaveKind.openingBalance:
          od += e.days;
          oa += e.amount;
        case PaidLeaveKind.taken:
          td += e.days;
        case PaidLeaveKind.payment:
          pa += e.amount;
      }
    }
    return PaidLeaveLedger(od, round2(oa), td, round2(pa));
  }
}

/// Conversion taux horaire net ↔ brut.
double netToGross(double net, double ratio) => ratio <= 0 ? net : round2(net / ratio);
double grossToNet(double gross, double ratio) => round2(gross * ratio);
