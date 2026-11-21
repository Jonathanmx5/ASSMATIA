import 'package:assmatia/domain/engine.dart';
import 'package:assmatia/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

// Lundi-vendredi 8h-17h = 9 h/j, 45 h/sem.
final sched9 = WeeklySchedule({
  for (var d = 1; d <= 5; d++) d: [const TimeSlot(8 * 60, 17 * 60)]
});
// Lundi-jeudi 9h-15h = 6 h/j, 24 h/sem.
final sched6 = WeeklySchedule({
  for (var d = 1; d <= 4; d++) d: [const TimeSlot(9 * 60, 15 * 60)]
});

ContractTerms terms({
  ContractType type = ContractType.fullYear,
  double rate = 4,
  int weeks = 52,
  WeeklySchedule? s,
  Allowances a = const Allowances(),
}) =>
    ContractTerms(
        type: type,
        hourlyRate: rate,
        weeksPerYear: weeks,
        schedule: s ?? sched9,
        allowances: a);

void main() {
  group('arrondi', () {
    test('au centime', () {
      expect(round2(1.005 * 1000) , 1005.0);
      expect(round2(12.344), 12.34);
      expect(round2(12.346), 12.35);
    });
  });

  group('mensualisation', () {
    test('année complète : 45h × 52 / 12 × 4 €', () {
      final t = terms();
      expect(t.monthlyHours, closeTo(195, 1e-9));
      expect(t.monthlySalary, 780.00);
    });
    test('année incomplète : semaines programmées', () {
      final t = terms(type: ContractType.partialYear, weeks: 36, s: sched6, rate: 4.15);
      // 24 × 36 / 12 = 72 h ; 72 × 4,15 = 298,80
      expect(t.monthlySalary, 298.80);
    });
    test('année complète ignore weeksPerYear', () {
      expect(terms(weeks: 40).effectiveWeeks, 52);
    });
  });

  group('avenants', () {
    final c = Contract(
      id: 'c',
      childId: 'k',
      startDate: DateTime(2026, 1, 1),
      base: terms(),
      amendments: [
        Amendment(id: 'a2', effectiveFrom: DateTime(2026, 9, 1), hourlyRate: 5),
        Amendment(id: 'a1', effectiveFrom: DateTime(2026, 4, 1), hourlyRate: 4.5, schedule: sched6),
      ],
    );
    test('avant tout avenant', () {
      expect(resolveTerms(c, DateTime(2026, 3, 31)).hourlyRate, 4);
    });
    test('avenant applicable le jour même', () {
      final t = resolveTerms(c, DateTime(2026, 4, 1));
      expect(t.hourlyRate, 4.5);
      expect(t.weeklyHours, 24);
    });
    test('cumul chronologique sans écraser les champs non modifiés', () {
      final t = resolveTerms(c, DateTime(2026, 10, 1));
      expect(t.hourlyRate, 5);
      expect(t.weeklyHours, 24); // planning de a1 conservé
    });
    test('mois antérieur non affecté', () {
      expect(computeMonth(c, 2026, 2, {}).baseSalary, 780.00);
    });
  });

  group('Cour de cassation', () {
    test('formule', () {
      expect(cassationDeduction(780, 9, 198), 35.45); // 780×9/198 = 35,4545
    });
    test('heures potentielles nulles', () {
      expect(cassationDeduction(780, 9, 0), 0.0);
    });
    test('dans le récapitulatif mensuel', () {
      final c = Contract(id: 'c', childId: 'k', startDate: DateTime(2026, 1, 1), base: terms());
      // Mars 2026 : 22 jours ouvrés → 198 h potentielles.
      expect(potentialHoursOfMonth(sched9, 2026, 3), 198);
      final logs = {
        '2026-03-02': DailyLog(childId: 'k', date: DateTime(2026, 3, 2), status: DayStatus.absentDeducted),
      };
      final s = computeMonth(c, 2026, 3, logs);
      expect(s.baseSalary, 780.00);
      expect(s.absenceDeduction, 35.45);
      expect(s.netSalary, 744.55);
      expect(s.daysPresent, 21);
    });
    test('absence non déduite', () {
      final c = Contract(id: 'c', childId: 'k', startDate: DateTime(2026, 1, 1), base: terms());
      final s = computeMonth(c, 2026, 3, {
        '2026-03-02': DailyLog(childId: 'k', date: DateTime(2026, 3, 2), status: DayStatus.absentNotDeducted),
      });
      expect(s.absenceDeduction, 0);
      expect(s.netSalary, 780);
    });
  });

  group('indemnités', () {
    final c = Contract(
      id: 'c',
      childId: 'k',
      startDate: DateTime(2026, 1, 1),
      base: terms(a: const Allowances(mealPerDay: 3.5, maintenancePerDay: 3.8, maintenancePerHour: 0.40)),
    );
    test('repas par jour, entretien = max(forfait, horaire × heures)', () {
      // 9 h × 0,40 = 3,60 < 3,80 → 3,80 ; 22 jours en mars
      final s = computeMonth(c, 2026, 3, {});
      expect(s.meals, 77.00);
      expect(s.maintenance, 83.60);
      expect(s.totalToPay, round2(780 + 77 + 83.6));
    });
    test('horaires effectifs et saisie manuelle', () {
      final s = computeMonth(c, 2026, 3, {
        '2026-03-02': DailyLog(
            childId: 'k',
            date: DateTime(2026, 3, 2),
            actualSlots: const [TimeSlot(7 * 60, 18 * 60)], // 11 h → 4,40
            mealOverride: 0),
      });
      expect(s.maintenance, round2(21 * 3.8 + 4.4));
      expect(s.meals, round2(21 * 3.5));
      expect(s.workedHours, 21 * 9 + 11);
    });
    test('pas d\'indemnité les jours d\'absence', () {
      final s = computeMonth(c, 2026, 3, {
        '2026-03-02': DailyLog(childId: 'k', date: DateTime(2026, 3, 2), status: DayStatus.absentDeducted),
      });
      expect(s.meals, round2(21 * 3.5));
    });
  });

  group('prorata entrée en cours de mois', () {
    test('début le 16 mars', () {
      final c = Contract(id: 'c', childId: 'k', startDate: DateTime(2026, 3, 16), base: terms());
      // 16→31 mars : 12 jours ouvrés = 108 h sur 198
      expect(computeMonth(c, 2026, 3, {}).baseSalary, round2(780 * 108 / 198));
    });
  });

  group('abattement fiscal', () {
    test('règle des 8 h et prorata', () {
      expect(dailyAllowanceDeduction(9, 11.88), round2(3 * 11.88));
      expect(dailyAllowanceDeduction(8, 11.88), closeTo(35.64, 1e-9));
      expect(dailyAllowanceDeduction(6, 12), 27.0); // 6/8 × 36
      expect(dailyAllowanceDeduction(0, 12), 0);
    });
    test('multi-enfants sur l\'année civile, revenu net plafonné à 0', () {
      final a = Contract(id: 'a', childId: 'A', startDate: DateTime(2026, 3, 16),
          endDate: DateTime(2026, 3, 31), base: terms());
      final b = Contract(id: 'b', childId: 'B', startDate: DateTime(2025, 6, 1),
          endDate: DateTime(2026, 1, 9), base: terms(s: sched6, rate: 4));
      final r = computeAnnualTax(
          year: 2026, scale: const TaxScale(2026, 12), contracts: [a, b], logsById: {});
      // A : 12 jours ≥ 8 h → 12 × 36 = 432
      // B : 1-9 janv. 2026 lun-jeu = 1 (jeudi),5,6,7,8 → 5 jours de 6 h → 135
      expect(r.careDays, 17);
      expect(r.totalAbatement, 567.0);
      expect(r.abatementByChild['A'], 432);
      expect(r.abatementByChild['B'], 135);
      final inc = round2(780 * 108 / 198 + r.incomeByChild['B']!);
      expect(r.taxableIncome, inc);
      expect(r.netTaxable, round2(inc - 567 < 0 ? 0 : inc - 567));
      final r2 = computeAnnualTax(
          year: 2026, scale: const TaxScale(2026, 12), contracts: [a, b], logsById: {},
          incomeOverride: 100);
      expect(r2.netTaxable, 0);
    });
  });
}
