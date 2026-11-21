import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../domain/models.dart';
import '../common.dart';

/// Espace parent : lecture seule du planning et des récapitulatifs mensuels
/// des enfants auxquels le parent est rattaché. Rechargé à chaque ouverture.
class ParentHome extends StatefulWidget {
  final ParentReader reader;
  final VoidCallback onSignOut;
  const ParentHome({super.key, required this.reader, required this.onSignOut});
  @override
  State<ParentHome> createState() => _ParentHomeState();
}

class _ParentHomeState extends State<ParentHome> {
  late Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> data = _load();

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _load() async =>
      (await widget.reader.plannings(), await widget.reader.summaries());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Espace parent'),
        actions: [
          IconButton(icon: const Icon(Icons.sync), onPressed: () => setState(() => data = _load())),
          IconButton(icon: const Icon(Icons.logout), onPressed: widget.onSignOut),
        ],
      ),
      body: FutureBuilder(
        future: data,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Center(child: Text('Erreur : ${snap.error}'));
          final (plannings, summaries) = snap.data!;
          if (plannings.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aucun enfant partagé avec cet e-mail. Demandez à votre '
                    'assistante maternelle de vous inviter.', textAlign: TextAlign.center),
              ),
            );
          }
          return ListView(padding: const EdgeInsets.all(8), children: [
            const Disclaimer(compact: true),
            for (final p in plannings) ..._child(context, p, summaries.where((s) => s['childId'] == p['childId']).toList()),
          ]);
        },
      ),
    );
  }

  List<Widget> _child(BuildContext context, Map<String, dynamic> p, List<Map<String, dynamic>> sums) {
    final color = (p['color'] as num).toInt();
    final sched = WeeklySchedule.fromJson(p['schedule'] == null ? null : Map<String, dynamic>.from(p['schedule']));
    sums.sort((a, b) => ((b['year'] as num) * 100 + (b['month'] as num)).compareTo((a['year'] as num) * 100 + (a['month'] as num)));
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ChildDot(color, size: 20),
              const SizedBox(width: 8),
              Text('${p['firstName']} — planning', style: Theme.of(context).textTheme.titleMedium),
            ]),
            const Divider(),
            for (var d = 1; d <= 7; d++)
              if (sched.slotsFor(d).isNotEmpty)
                Line(weekdayNames[d - 1], sched.slotsFor(d).join(', ')),
            Line('Total hebdomadaire', hrs(sched.weeklyHours), bold: true),
          ]),
        ),
      ),
      for (final s in sums)
        ExpansionTile(
          title: Text('${p['firstName']} — ${monthLabel((s['year'] as num).toInt(), (s['month'] as num).toInt())}'),
          subtitle: Text('Total : ${eur(round2(((s['netSalary'] ?? 0) as num) + ((s['meals'] ?? 0) as num) + ((s['maintenance'] ?? 0) as num)))}'),
          children: [SummaryCard(title: '${p['firstName']}', color: color, s: s)],
        ),
    ];
  }
}
