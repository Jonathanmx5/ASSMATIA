import 'package:flutter/material.dart';

import '../../data/nanny_store.dart';
import '../../domain/engine.dart';
import '../../domain/models.dart';
import '../common.dart';
import '../theme.dart';

const kNonProgrammedLabel = 'Semaine non programmée';

/// Année incomplète : choix des semaines d'accueil de l'année de contrat.
/// Une semaine décochée devient une période sans accueil pour cet enfant
/// (ni accueil, ni indemnité, ni déduction, ni abattement).
class ProgrammedWeeksScreen extends StatefulWidget {
  final NannyStore store;
  final Contract contract;
  const ProgrammedWeeksScreen({super.key, required this.store, required this.contract});
  @override
  State<ProgrammedWeeksScreen> createState() => _ProgrammedWeeksScreenState();
}

class _ProgrammedWeeksScreenState extends State<ProgrammedWeeksScreen> {
  late int yearIndex = _currentYearIndex();

  Contract get c => widget.contract;
  NannyStore get s => widget.store;

  /// Année de contrat n° [i] : du début du contrat + i ans, sur 12 mois.
  DateTime _yearStart(int i) => DateTime(c.startDate.year + i, c.startDate.month, c.startDate.day);

  int _currentYearIndex() {
    final now = DateTime.now();
    var i = 0;
    while (!_yearStart(i + 1).isAfter(now)) {
      i++;
    }
    return i;
  }

  List<DateTime> _weeks() {
    final start = _yearStart(yearIndex), end = _yearStart(yearIndex + 1);
    var m = addDays(start, -(start.weekday - 1));
    final out = <DateTime>[];
    while (m.isBefore(end)) {
      out.add(m);
      m = addDays(m, 7);
    }
    return out;
  }

  String _id(DateTime monday) => 'npw_${c.childId}_${dateKey(monday)}';

  bool _hasCare(DateTime monday) {
    for (var i = 0; i < 7; i++) {
      final d = addDays(monday, i);
      if (c.isActiveOn(d) && resolveTerms(c, d).schedule.hoursFor(d.weekday) > 0) return true;
    }
    return false;
  }

  bool _programmed(DateTime monday) => !s.leaves.containsKey(_id(monday));

  Future<void> _toggle(DateTime monday) async {
    final id = _id(monday);
    final p = s.leaves[id];
    if (p != null) {
      await s.deleteLeave(p);
    } else {
      await s.saveLeave(LeavePeriod(
          id: id, from: monday, to: addDays(monday, 6), label: kNonProgrammedLabel, childIds: [c.childId]));
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final weeks = _weeks().where(_hasCare).toList();
    final programmed = weeks.where(_programmed).length;
    final expected = resolveTerms(c, _yearStart(yearIndex).isBefore(c.startDate) ? c.startDate : _yearStart(yearIndex)).weeksPerYear;
    final ok = programmed == expected;
    final child = s.children[c.childId];
    return Scaffold(
      appBar: AppBar(title: Text('Semaines · ${child?.firstName ?? ''}')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          Row(children: [
            IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: yearIndex == 0 ? null : () => setState(() => yearIndex--)),
            Expanded(
              child: Center(
                child: Text('${fmtDate(_yearStart(yearIndex))} → ${fmtDate(addDays(_yearStart(yearIndex + 1), -1))}',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: () => setState(() => yearIndex++)),
          ]),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (ok ? Kid.mint : Kid.sun).withValues(alpha: .2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              Icon(ok ? Icons.check_circle_rounded : Icons.info_rounded, color: ok ? Kid.mint : Colors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ok
                      ? '$programmed semaines programmées : conforme au contrat.'
                      : '$programmed semaines programmées pour $expected prévues au contrat. '
                          'Décochez les semaines sans accueil (vacances des parents, fermetures).',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ]),
          ),
          for (final m in weeks)
            CheckboxListTile(
              value: _programmed(m),
              onChanged: s.isLocked(c.childId, m.year, m.month) ? null : (_) => _toggle(m),
              title: Text('Semaine du ${fmtDate(m)}'),
              subtitle: Text(_programmed(m) ? 'Accueil prévu' : kNonProgrammedLabel),
              secondary: Icon(_programmed(m) ? Icons.child_care_rounded : Icons.beach_access_rounded,
                  color: _programmed(m) ? Kid.sky : Kid.sun),
            ),
        ]),
      ),
    );
  }
}
