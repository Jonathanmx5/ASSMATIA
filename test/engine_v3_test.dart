import 'package:assmatia/domain/engine.dart';
import 'package:assmatia/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

// Lundi-vendredi 8h-17h = 9 h/j, 45 h/sem.
final sched9 = WeeklySchedule({
  for (var d = 1; d <= 5; d++) d: [const TimeSlot(480, 1020)]
});
// Lundi-jeudi 8h-16h = 8 h/j, 32 h/sem.
final sched8 = WeeklySchedule({
  for (var d = 1; d <= 4; d++) d: [const TimeSlot(480, 960)]
});

Contract contract(WeeklySchedule s, {double maj = 25}) => Contract(
      id: 'c',
      childId: 'k',
      startDate: DateTime(2026, 1, 1),
      base: ContractTerms(
          type: ContractType.fullYear,
          hourlyRate: 4,
          weeksPerYear: 52,
          schedule: s,
          allowances: Allowances(maintenancePerDay: 3, maintenancePerHour: .4, overtimeMajorationPct: maj)),
    );

DailyLog late(DateTime d, double h) => DailyLog(childId: 'k', date: d, extraHours: h);

void main() {
  group('heures en plus (retards)', () {
    test('sous 45 h/sem. : payées au taux normal', () {
      // 32 h prévues + 2 h de retard le lundi 2 mars = 34 h < 45 h
      final s = computeMonth(contract(sched8), 2026, 3, {'2026-03-02': late(DateTime(2026, 3, 2), 2)});
      expect(s.extraHours, 2);
      expect(s.extraPay, 8.0);
      expect(s.grossSalary, round2(s.baseSalary + 8));
    });

    test('au-delà de 45 h/sem. : majorées au taux du contrat', () {
      // 45 h prévues + 1,5 h le lundi et 1 h le mardi = 47,5 h → 2,5 h majorées à 25 %
      final s = computeMonth(contract(sched9), 2026, 3, {
        '2026-03-02': late(DateTime(2026, 3, 2), 1.5),
        '2026-03-03': late(DateTime(2026, 3, 3), 1),
      });
      expect(s.extraHours, 2.5);
      expect(s.extraPay, round2(2.5 * 4 * 1.25));
    });

    test('mixte : une partie normale, une partie majorée', () {
      // 40 h prévues (4 × 10 h) + 7 h en plus = 47 h → 5 h normales + 2 h majorées
      final s10 = WeeklySchedule({for (var d = 1; d <= 4; d++) d: [const TimeSlot(480, 1080)]});
      final s = computeMonth(contract(s10, maj: 10), 2026, 3, {'2026-03-02': late(DateTime(2026, 3, 2), 7)});
      expect(s.extraPay, round2(5 * 4 + 2 * 4 * 1.10));
    });

    test('indemnité d\'entretien recalculée avec les heures en plus', () {
      // 9 h + 2 h = 11 h × 0,40 = 4,40 > forfait 3 €
      final r = computeDay(contract(sched9).base, DateTime(2026, 3, 2), late(DateTime(2026, 3, 2), 2));
      expect(r.workedHours, 11);
      expect(round2(r.maintenance), 4.40);
    });

    test('jamais d\'heures en plus sur une absence', () {
      final r = computeDay(contract(sched9).base, DateTime(2026, 3, 2),
          DailyLog(childId: 'k', date: DateTime(2026, 3, 2), status: DayStatus.absentDeducted, extraHours: 3));
      expect(r.workedHours, 0);
      expect(r.extraHours, 0);
    });

    test('abattement fiscal : journée allongée comptée en heures réelles', () {
      // 6 h prévues + 2 h = 8 h → abattement plein
      final s6 = WeeklySchedule({1: [const TimeSlot(540, 900)]});
      final c = Contract(id: 'c', childId: 'k', startDate: DateTime(2026, 3, 2), endDate: DateTime(2026, 3, 2), base: contract(s6).base);
      final r = computeAnnualTax(
          year: 2026,
          scale: const TaxScale(2026, 12),
          contracts: [c],
          logsById: {'k_2026-03-02': late(DateTime(2026, 3, 2), 2)});
      expect(r.totalAbatement, 36);
    });
  });

  group('simulation de fin de mois', () {
    test('le mois projeté compte tous les jours prévus', () {
      final ctx = CalcContext(asOf: DateTime(2026, 3, 13));
      final now = computeMonth(contract(sched9), 2026, 3, {}, ctx: ctx);
      final proj = computeMonth(contract(sched9), 2026, 3, {}, ctx: ctx.projected());
      expect(now.daysPresent, 10);
      expect(proj.daysPresent, 22);
      expect(proj.provisional, isFalse);
      expect(proj.maintenance, greaterThan(now.maintenance));
    });
  });

  group('congés payés : historique', () {
    test('solde repris, jours pris et paiements', () {
      final l = PaidLeaveLedger.of([
        PaidLeaveEntry(id: '1', contractId: 'c', date: DateTime(2025, 6, 1), kind: PaidLeaveKind.openingBalance, days: 12, amount: 300),
        PaidLeaveEntry(id: '2', contractId: 'c', date: DateTime(2025, 8, 1), kind: PaidLeaveKind.taken, days: 10),
        PaidLeaveEntry(id: '3', contractId: 'c', date: DateTime(2026, 6, 30), kind: PaidLeaveKind.payment, amount: 250.5),
      ]);
      expect(l.openingDays, 12);
      expect(l.openingAmount, 300);
      expect(l.takenDays, 10);
      expect(l.paidAmount, 250.5);
    });
  });

  test('conversion net ↔ brut', () {
    expect(netToGross(3.12, .78), 4.0);
    expect(grossToNet(4, .78), 3.12);
  });

  group("changement d'heure (fin octobre)", () {
    test('addDays reste sur la bonne date', () {
      expect(dateKey(addDays(DateTime(2026, 10, 25), 1)), '2026-10-26');
      expect(dateKey(addDays(DateTime(2026, 10, 26), -1)), '2026-10-25');
      expect(dateKey(addDays(DateTime(2026, 3, 29), 1)), '2026-03-30');
    });
    test('heures en plus : la semaine du 26/10 regroupée correctement', () {
      // Dimanche 25/10 (changement d'heure) puis semaine du 26 au 30/10.
      final s = computeMonth(contract(sched9), 2026, 10, {
        '2026-10-30': late(DateTime(2026, 10, 30), 1),
      });
      expect(s.extraPay, round2(1 * 4 * 1.25)); // 46 h dans la semaine → majorée
    });
  });

  group('déclaration Pajemploi', () {
    test('heures normales = mensualisées − absences + heures en plus non majorées', () {
      // 45 h/sem × 52 / 12 = 195 h ; absence du lundi 2 (9 h) ; 1 h en plus le mardi 3 (semaine 37 h + 1 = 37 h < 45)
      final s = computeMonth(contract(sched9), 2026, 3, {
        '2026-03-02': DailyLog(childId: 'k', date: DateTime(2026, 3, 2), status: DayStatus.absentDeducted),
        '2026-03-03': late(DateTime(2026, 3, 3), 1),
      });
      final p = PajemploiDeclaration.of(s);
      expect(s.paidHours, 195);
      expect(p.normalHours, 195 - 9 + 1);
      expect(p.majoredHours, 0);
      expect(p.activityDays, 21);
      expect(p.netSalary, s.netSalary);
    });
    test('heures majorées séparées', () {
      final s = computeMonth(contract(sched9), 2026, 3, {'2026-03-02': late(DateTime(2026, 3, 2), 2)});
      final p = PajemploiDeclaration.of(s);
      expect(p.majoredHours, 2);
      expect(p.normalHours, 195);
    });
  });

  test('Cour de cassation : semaines non programmées exclues des heures potentielles', () {
    // Mars 2026 : 198 h potentielles ; semaine du 9 au 13 non programmée → 153 h.
    final ctx = CalcContext(leaves: [
      LeavePeriod(id: 'w', from: DateTime(2026, 3, 9), to: DateTime(2026, 3, 15), childIds: ['k']),
    ]);
    final s = computeMonth(contract(sched9), 2026, 3, {
      '2026-03-02': DailyLog(childId: 'k', date: DateTime(2026, 3, 2), status: DayStatus.absentDeducted),
    }, ctx: ctx);
    expect(s.baseSalary, 780); // mensualisation inchangée
    expect(s.potentialHours, 153);
    expect(s.absenceDeduction, round2(780 * 9 / 153));
  });
}
