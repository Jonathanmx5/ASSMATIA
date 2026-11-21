import 'package:flutter/material.dart';

import '../../data/nanny_store.dart';
import '../../domain/engine.dart';
import '../../domain/models.dart';
import '../common.dart';

/// Vue semaine multi-enfants : qui est accueilli, quels jours, quels horaires.
class PlanningTab extends StatefulWidget {
  final NannyStore store;
  const PlanningTab({super.key, required this.store});
  @override
  State<PlanningTab> createState() => _PlanningTabState();
}

class _PlanningTabState extends State<PlanningTab> {
  late DateTime monday = _monday(DateTime.now());
  static DateTime _monday(DateTime d) => dayOnly(d).subtract(Duration(days: d.weekday - 1));

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return Column(children: [
      Row(children: [
        IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => monday = monday.subtract(const Duration(days: 7)))),
        Expanded(
          child: TextButton(
            onPressed: () => setState(() => monday = _monday(DateTime.now())),
            child: Text('Semaine du ${fmtDate(monday)}'),
          ),
        ),
        IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => monday = monday.add(const Duration(days: 7)))),
      ]),
      Expanded(
        child: ListView(children: [
          for (var i = 0; i < 7; i++) _day(context, s, monday.add(Duration(days: i))),
        ]),
      ),
    ]);
  }

  Widget _day(BuildContext context, NannyStore s, DateTime d) {
    final rows = <Widget>[];
    var total = 0;
    for (final c in s.activeChildren) {
      final ct = s.contractOn(c.id, d);
      if (ct == null) continue;
      final t = resolveTerms(ct, d);
      final log = s.logOf(c.id, d);
      final slots = log?.actualSlots ?? t.schedule.slotsFor(d.weekday);
      final kind = s.kindOf(c.id, d);
      final off = log == null && (kind == DayKind.leave || kind == DayKind.publicHoliday);
      final absent = off || (log != null && log.status != DayStatus.present);
      if (slots.isEmpty) continue;
      total++;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          ChildDot(c.color),
          const SizedBox(width: 6),
          SizedBox(width: 90, child: Text(c.firstName, overflow: TextOverflow.ellipsis)),
          Expanded(child: _Timeline(slots: slots, color: c.color, faded: absent)),
          SizedBox(
            width: 92,
            child: Text(off ? (kind == DayKind.leave ? 'Congés' : 'Férié') : absent ? 'Absent' : slots.join('\n'),
                textAlign: TextAlign.right, style: const TextStyle(fontSize: 11)),
          ),
        ]),
      ));
    }
    final today = dayOnly(DateTime.now()) == d;
    return Card(
      color: today ? Theme.of(context).colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${weekdayNames[d.weekday - 1]} ${fmtDate(d)} · $total enfant(s)',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          if (rows.isEmpty) const Text('Aucun accueil', style: TextStyle(fontSize: 12)),
          ...rows,
        ]),
      ),
    );
  }
}

/// Barre 6h–20h montrant les tranches d'accueil.
class _Timeline extends StatelessWidget {
  final List<TimeSlot> slots;
  final int color;
  final bool faded;
  const _Timeline({required this.slots, required this.color, this.faded = false});
  static const startH = 6, endH = 20;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, cons) {
        final w = cons.maxWidth;
        double x(int m) => ((m / 60 - startH) / (endH - startH)).clamp(0.0, 1.0) * w;
        return Container(
          height: 14,
          decoration: BoxDecoration(color: Colors.grey.withValues(alpha: .15), borderRadius: BorderRadius.circular(4)),
          child: Stack(children: [
            for (final s in slots)
              Positioned(
                left: x(s.startMin),
                width: (x(s.endMin) - x(s.startMin)).clamp(2.0, w),
                top: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Color(color).withValues(alpha: faded ? .3 : 1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
          ]),
        );
      });
}
