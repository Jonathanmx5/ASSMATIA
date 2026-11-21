import 'package:assmatia/domain/engine.dart';
import 'package:assmatia/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

final sched9 = WeeklySchedule({
  for (var d = 1; d <= 5; d++) d: [const TimeSlot(8 * 60, 17 * 60)]
});

Contract contract({ContractType type = ContractType.fullYear, int weeks = 52, DateTime? start, DateTime? end}) => Contract(
      id: 'c',
      childId: 'k',
      startDate: start ?? DateTime(2025, 1, 1),
      endDate: end,
      base: ContractTerms(
          type: type,
          hourlyRate: 4,
          weeksPerYear: weeks,
          schedule: sched9,
          allowances: const Allowances(mealPerDay: 3, maintenancePerDay: 4)),
    );

void main() {
  test('jours fériés 2026 (Pâques le 5 avril)', () {
    final h = frenchPublicHolidays(2026);
    expect(h, containsAll(['2026-01-01', '2026-04-06', '2026-05-14', '2026-05-25', '2026-07-14', '2026-12-25']));
    expect(h.length, 11);
  });

  test('férié : salaire inchangé, pas d\'indemnité ni d\'abattement', () {
    // Mai 2026 : 21 jours ouvrés dont 1, 8, 14, 25 fériés (vendredi, vendredi, jeudi, lundi).
    final s = computeMonth(contract(), 2026, 5, {});
    expect(s.baseSalary, 780);
    expect(s.absenceDeduction, 0);
    expect(s.daysPresent, 21 - 4);
    expect(s.meals, 3.0 * 17);
  });

  test('congés : aucun accueil, aucune déduction', () {
    final ctx = CalcContext(leaves: [
      LeavePeriod(id: 'l', from: DateTime(2026, 3, 2), to: DateTime(2026, 3, 6)),
    ]);
    final s = computeMonth(contract(), 2026, 3, {}, ctx: ctx);
    expect(s.grossSalary, 780);
    expect(s.daysPresent, 22 - 5);
  });

  test('congés ciblés sur un autre enfant : sans effet', () {
    final ctx = CalcContext(leaves: [
      LeavePeriod(id: 'l', from: DateTime(2026, 3, 2), to: DateTime(2026, 3, 6), childIds: ['autre']),
    ]);
    expect(computeMonth(contract(), 2026, 3, {}, ctx: ctx).daysPresent, 22);
  });

  test('jours futurs : prévisionnel, non comptés comme effectués', () {
    final ctx = CalcContext(asOf: DateTime(2026, 3, 13)); // vendredi
    final s = computeMonth(contract(), 2026, 3, {}, ctx: ctx);
    expect(s.provisional, isTrue);
    expect(s.daysPresent, 10);
    expect(s.baseSalary, 780); // mensualisation inchangée
  });

  test('pointage explicite prime sur un jour futur ou férié', () {
    final ctx = CalcContext(asOf: DateTime(2026, 3, 1));
    final s = computeMonth(contract(), 2026, 3, {
      '2026-03-02': DailyLog(childId: 'k', date: DateTime(2026, 3, 2)),
    }, ctx: ctx);
    expect(s.daysPresent, 1);
  });

  test('abattement : seulement les jours effectifs à la date d\'arrêté', () {
    final r = computeAnnualTax(
      year: 2026,
      scale: const TaxScale(2026, 12),
      contracts: [contract(start: DateTime(2026, 3, 2), end: DateTime(2026, 3, 31))],
      logsById: {},
      ctx: CalcContext(asOf: DateTime(2026, 3, 6)),
    );
    expect(r.careDays, 5);
    expect(r.totalAbatement, 180);
    expect(r.partial, isTrue);
  });

  test('brut → net selon le taux', () {
    final s = computeMonth(contract(), 2026, 3, {}, ctx: CalcContext(netRatio: 0.8));
    expect(s.grossSalary, 780);
    expect(s.netSalary, 624);
  });

  group('congés payés', () {
    test('année complète sur 12 mois : 30 jours, inclus dans la mensualisation', () {
      final p = computePaidLeave(contract(), 2026, {})!;
      expect(p.monthsWorked, 12);
      expect(p.daysAcquired, 30);
      expect(p.grossReference, 780 * 12);
      expect(p.tenPercent, 936);
      expect(p.maintien, 900); // 780 / 26 × 30
      expect(p.retained, 936);
      expect(p.includedInMonthly, isTrue);
      expect(p.toPayExtra, 36);
    });
    test('année incomplète : à verser en plus', () {
      final p = computePaidLeave(contract(type: ContractType.partialYear, weeks: 40), 2026, {})!;
      // 45 × 40 / 12 = 150 h → 600 €/mois
      expect(p.tenPercent, 720);
      expect(p.maintien, round2(600 / 26 * 30));
      expect(p.includedInMonthly, isFalse);
      expect(p.toPayExtra, 720);
    });
    test('démarrage en cours de période : prorata des mois', () {
      final p = computePaidLeave(contract(start: DateTime(2026, 1, 1)), 2026, {})!;
      expect(p.monthsWorked, 5);
      expect(p.daysAcquired, 13); // 12,5 arrondi au supérieur
    });
    test('aucun mois : null', () {
      expect(computePaidLeave(contract(start: DateTime(2027, 1, 1)), 2026, {}), isNull);
    });
  });

  group('contrôles', () {
    test('tranches qui se chevauchent', () {
      expect(slotsOverlap(const [TimeSlot(480, 720), TimeSlot(700, 900)]), isTrue);
      expect(slotsOverlap(const [TimeSlot(480, 720), TimeSlot(720, 900)]), isFalse);
      expect(slotsOverlap(const [TimeSlot(600, 500)]), isTrue);
    });
    test('contrats qui se chevauchent', () {
      final a = contract(start: DateTime(2026, 1, 1), end: DateTime(2026, 6, 30));
      final b = Contract(id: 'b', childId: 'k', startDate: DateTime(2026, 6, 30), base: a.base);
      final c = Contract(id: 'c2', childId: 'k', startDate: DateTime(2026, 7, 1), base: a.base);
      expect(contractsOverlap(a, b), isTrue);
      expect(contractsOverlap(a, c), isFalse);
    });
  });
}
