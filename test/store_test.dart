import 'package:assmatia/data/backend.dart';
import 'package:assmatia/data/nanny_store.dart';
import 'package:assmatia/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Backend en mémoire simulant Firestore (partage activé).
class MemoryBackend implements NannyBackend {
  final Data data = {};
  bool fail = false;
  @override
  void Function(Object error)? onError;
  @override
  bool get supportsSharing => true;
  @override
  Future<Data> loadAll() async => data;
  @override
  void write(List<WriteOp> ops) {
    if (fail) return onError?.call('réseau');
    for (final op in ops) {
      if (op.data == null) {
        data[op.collection]?.remove(op.id);
      } else {
        (data[op.collection] ??= {})[op.id] = {...op.data!, 'nannyId': 'n'};
      }
    }
  }

  @override
  Future<List<String>> idsWhere(String collection, String field, Object value) async =>
      [for (final e in (data[collection] ?? {}).entries) if (e.value[field] == value) e.key];
}

final terms = ContractTerms(
  type: ContractType.fullYear,
  hourlyRate: 4,
  weeksPerYear: 52,
  schedule: WeeklySchedule({for (var d = 1; d <= 5; d++) d: [const TimeSlot(480, 1020)]}),
  allowances: const Allowances(),
);

Future<(NannyStore, MemoryBackend)> setup() async {
  final b = MemoryBackend();
  final s = NannyStore(b)..now = () => DateTime(2026, 3, 15);
  await s.load();
  await s.saveChild(const Child(id: 'k', firstName: 'Lina', color: 0, parentEmails: ['p@x.fr']));
  await s.saveContract(Contract(id: 'c', childId: 'k', startDate: DateTime(2025, 1, 1), base: terms));
  return (s, b);
}

void main() {
  test('publie tous les mois depuis le début du contrat', () async {
    final (_, b) = await setup();
    // janv. 2025 → avril 2026 = 16 mois
    expect(b.data[kSummaries]!.length, 16);
    expect(b.data[kSharedPlannings]!['k']!['parentEmails'], ['p@x.fr']);
  });

  test('retirer un parent révoque tout l\'historique', () async {
    final (s, b) = await setup();
    await s.saveChild(s.children['k']!.copyWith(parentEmails: []));
    for (final d in b.data[kSummaries]!.values) {
      expect(d['parentEmails'], isEmpty);
    }
  });

  test('supprimer le contrat supprime les récaps publiés', () async {
    final (s, b) = await setup();
    await s.deleteContract(s.contracts['c']!);
    expect(b.data[kSummaries], isEmpty);
  });

  test('mois validé : figé malgré un avenant ultérieur', () async {
    final (s, _) = await setup();
    await s.lockMonth('k', 2026, 1);
    final before = s.summary('k', 2026, 1)!.grossSalary;
    final c = s.contracts['c']!;
    await s.saveContract(c.copyWith(amendments: [Amendment(id: 'a', effectiveFrom: DateTime(2025, 6, 1), hourlyRate: 10)]));
    expect(s.summary('k', 2026, 1)!.grossSalary, before);
    expect(s.summary('k', 2026, 1)!.locked, isTrue);
    expect(s.summary('k', 2026, 2)!.grossSalary, greaterThan(before));
    await s.unlockMonth('k', 2026, 1);
    expect(s.summary('k', 2026, 1)!.grossSalary, greaterThan(before));
  });

  test('export puis import dans un compte vierge', () async {
    final (s, _) = await setup();
    final s2 = NannyStore(MemoryBackend());
    await s2.load();
    await s2.importData(s.snapshot());
    expect(s2.children['k']!.firstName, 'Lina');
    expect(s2.summary('k', 2026, 2)!.grossSalary, s.summary('k', 2026, 2)!.grossSalary);
    expect(s.exportJson(), contains('"app": "ASSMATIA"'));
  });

  test('chevauchement de contrats détecté', () async {
    final (s, _) = await setup();
    expect(s.overlapping(Contract(id: 'x', childId: 'k', startDate: DateTime(2026, 1, 1), base: terms)), isNotNull);
  });

  test('échec d\'écriture remonté à l\'interface', () async {
    final (s, b) = await setup();
    b.fail = true;
    await s.saveChild(s.children['k']!.copyWith(firstName: 'Léa'));
    expect(s.lastError, contains('réseau'));
    expect(s.children['k']!.firstName, 'Léa'); // l'UI n'est pas bloquée
  });
}
