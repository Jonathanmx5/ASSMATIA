import 'package:flutter/material.dart';

import '../../data/nanny_store.dart';
import '../../domain/engine.dart';
import '../../domain/models.dart';
import '../common.dart';
import '../theme.dart';

/// Calendrier des exceptions : le planning type fait foi ; on ne saisit que
/// les absences, les congés et les heures en plus, sur un ou plusieurs jours.
class CalendarTab extends StatefulWidget {
  final NannyStore store;
  const CalendarTab({super.key, required this.store});
  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

enum _Mark { none, planned, absentDeducted, absentNotDeducted, leave, holiday, extra }

class _CalendarTabState extends State<CalendarTab> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  final Set<String> selectedDays = {};
  Set<String>? childFilter; // null = tous les enfants actifs

  NannyStore get s => widget.store;
  List<Child> get kids => s.activeChildren.where((c) => childFilter == null || childFilter!.contains(c.id)).toList();

  _Mark markOf(Child c, DateTime d) {
    final ct = s.contractOn(c.id, d);
    if (ct == null) return _Mark.none;
    final log = s.logOf(c.id, d);
    if (log != null) {
      switch (log.status) {
        case DayStatus.absentDeducted:
          return _Mark.absentDeducted;
        case DayStatus.absentNotDeducted:
        case DayStatus.notScheduled:
          return _Mark.absentNotDeducted;
        case DayStatus.present:
          if (log.extraHours > 0) return _Mark.extra;
      }
    }
    final planned = resolveTerms(ct, d).schedule.hoursFor(d.weekday) > 0;
    if (!planned) return _Mark.none;
    return switch (s.kindOf(c.id, d)) {
      DayKind.leave => _Mark.leave,
      DayKind.publicHoliday => _Mark.holiday,
      _ => _Mark.planned,
    };
  }

  static Color colorOf(_Mark m) => switch (m) {
        _Mark.absentDeducted => Kid.coral,
        _Mark.absentNotDeducted => Kid.pink,
        _Mark.leave => Kid.sun,
        _Mark.holiday => const Color(0xFFB0AAC8),
        _Mark.extra => Kid.mint,
        _ => Kid.sky,
      };

  static String labelOf(_Mark m) => switch (m) {
        _Mark.absentDeducted => 'Absent (déduit)',
        _Mark.absentNotDeducted => 'Absent (non déduit)',
        _Mark.leave => 'Congés',
        _Mark.holiday => 'Férié',
        _Mark.extra => 'Heures en plus',
        _Mark.planned => 'Selon planning',
        _Mark.none => '',
      };

  List<DateTime> get _selected => selectedDays.map(parseDateKey).toList()..sort();

  /// Jours sélectionnés où l'enfant a un contrat, un accueil prévu et un mois non validé.
  List<DateTime> _targetDays(Child c) => _selected.where((d) {
        final ct = s.contractOn(c.id, d);
        return ct != null &&
            resolveTerms(ct, d).schedule.hoursFor(d.weekday) > 0 &&
            !s.isLocked(c.id, d.year, d.month);
      }).toList();

  Future<void> _apply(String action) async {
    double extra = 0;
    if (action == 'extra') {
      final v = await _askHours();
      if (v == null || v <= 0) return;
      extra = v;
    }
    var count = 0;
    for (final c in kids) {
      final days = _targetDays(c);
      if (days.isEmpty) continue;
      count += days.length;
      switch (action) {
        case 'absentDeducted':
        case 'absentNotDeducted':
          await s.removeLeaveDays(c.id, days);
          await s.saveLogs([
            for (final d in days)
              DailyLog(
                childId: c.id,
                date: d,
                status: action == 'absentDeducted' ? DayStatus.absentDeducted : DayStatus.absentNotDeducted,
                absenceHours: action == 'absentDeducted'
                    ? resolveTerms(s.contractOn(c.id, d)!, d).schedule.hoursFor(d.weekday)
                    : 0,
              )
          ]);
        case 'leave':
          await s.deleteLogs([for (final d in days) if (s.logOf(c.id, d) != null) s.logOf(c.id, d)!]);
          await s.removeLeaveDays(c.id, days);
          await s.addLeaveDays(c.id, days, 'Congés');
        case 'extra':
          await s.removeLeaveDays(c.id, days);
          await s.saveLogs([for (final d in days) DailyLog(childId: c.id, date: d, extraHours: extra)]);
        case 'clear':
          await s.deleteLogs([for (final d in days) if (s.logOf(c.id, d) != null) s.logOf(c.id, d)!]);
          await s.removeLeaveDays(c.id, days);
      }
    }
    if (!mounted) return;
    setState(selectedDays.clear);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(count == 0
            ? "Aucun jour d'accueil prévu dans la sélection (ou mois validé)."
            : '$count journée(s) mise(s) à jour.')));
  }

  Future<double?> _askHours() async {
    final ctl = TextEditingController(text: '1');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Heures en plus'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Retard des parents : temps de garde supplémentaire par jour sélectionné.'),
          const SizedBox(height: 12),
          TextField(
            controller: ctl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Durée', suffixText: 'h', helperText: 'Ex. 0,5 pour 30 min'),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final q in ['0,25', '0,5', '1', '1,5', '2'])
              ActionChip(label: Text('$q h'), onPressed: () => ctl.text = q),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Valider')),
        ],
      ),
    );
    return v == null ? null : parseNum(v);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final first = DateTime(month.year, month.month, 1);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1;
    final today = dayOnly(DateTime.now());
    final list = kids;
    // Exceptions du mois (hors planning normal).
    final exceptions = <(Child, DateTime, _Mark)>[];
    for (var i = 1; i <= days; i++) {
      final d = DateTime(month.year, month.month, i);
      for (final c in list) {
        final m = markOf(c, d);
        if (m != _Mark.planned && m != _Mark.none && m != _Mark.holiday) exceptions.add((c, d, m));
      }
    }
    return Stack(children: [
      ListView(padding: const EdgeInsets.only(bottom: 160), children: [
        // Filtre enfants
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: const Text('Tous'),
                selected: childFilter == null,
                onSelected: (_) => setState(() => childFilter = null),
              ),
            ),
            for (final c in s.activeChildren)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  avatar: ChildAvatar(name: c.firstName, color: c.color, size: 24),
                  label: Text(c.firstName),
                  selected: childFilter?.contains(c.id) ?? false,
                  onSelected: (v) => setState(() {
                    final f = {...?childFilter};
                    v ? f.add(c.id) : f.remove(c.id);
                    childFilter = f.isEmpty ? null : f;
                  }),
                ),
              ),
          ]),
        ),
        Row(children: [
          IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => setState(() {
                    month = DateTime(month.year, month.month - 1);
                    selectedDays.clear();
                  })),
          Expanded(child: Center(child: Text(monthLabel(month.year, month.month), style: tt.titleLarge))),
          IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: () => setState(() {
                    month = DateTime(month.year, month.month + 1);
                    selectedDays.clear();
                  })),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            "Le planning s'applique automatiquement. Touchez un ou plusieurs jours pour noter une absence, "
            'des congés ou des heures en plus.',
            style: tt.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              Row(children: [
                for (final w in weekdayShort)
                  Expanded(child: Center(child: Text(w.substring(0, 1), style: const TextStyle(fontWeight: FontWeight.w800)))),
              ]),
              const SizedBox(height: 4),
              GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: .82,
                children: [
                  for (var i = 0; i < lead; i++) const SizedBox(),
                  for (var i = 1; i <= days; i++) _cell(DateTime(month.year, month.month, i), list, today),
                ],
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Wrap(spacing: 12, runSpacing: 4, children: [
            for (final m in [_Mark.planned, _Mark.absentDeducted, _Mark.absentNotDeducted, _Mark.leave, _Mark.extra, _Mark.holiday])
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: colorOf(m), shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(labelOf(m), style: const TextStyle(fontSize: 12)),
              ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Exceptions du mois', style: tt.titleMedium),
        ),
        if (exceptions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Aucune : tout le mois suit le planning.'),
          ),
        for (final (c, d, m) in exceptions)
          ListTile(
            dense: true,
            leading: ChildAvatar(name: c.firstName, color: c.color, size: 32),
            title: Text('${c.firstName} · ${weekdayNames[d.weekday - 1]} ${fmtDate(d)}'),
            subtitle: Text(m == _Mark.extra ? '+ ${hrs(s.logOf(c.id, d)!.extraHours)}' : labelOf(m),
                style: TextStyle(color: colorOf(m), fontWeight: FontWeight.w800)),
            trailing: s.isLocked(c.id, d.year, d.month)
                ? const Icon(Icons.lock_rounded, size: 18)
                : IconButton(
                    tooltip: 'Revenir au planning',
                    icon: const Icon(Icons.undo_rounded),
                    onPressed: () async {
                      final l = s.logOf(c.id, d);
                      if (l != null) await s.deleteLog(l);
                      await s.removeLeaveDays(c.id, [d]);
                      if (mounted) setState(() {});
                    },
                  ),
          ),
      ]),
      if (selectedDays.isNotEmpty) Positioned(left: 8, right: 8, bottom: 8, child: _actionBar()),
    ]);
  }

  Widget _cell(DateTime d, List<Child> list, DateTime today) {
    final key = dateKey(d);
    final sel = selectedDays.contains(key);
    final marks = [for (final c in list) markOf(c, d)].where((m) => m != _Mark.none).toList();
    final isToday = d == today;
    return GestureDetector(
      onTap: () => setState(() => sel ? selectedDays.remove(key) : selectedDays.add(key)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: sel ? Kid.lavender.withValues(alpha: .25) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: sel ? const Color(0xFF7B5CE6) : isToday ? Kid.sun : Colors.transparent, width: sel || isToday ? 2 : 1),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${d.day}', style: TextStyle(fontWeight: FontWeight.w800, color: d.weekday >= 6 ? Colors.grey : null)),
          const SizedBox(height: 3),
          Wrap(alignment: WrapAlignment.center, spacing: 2, runSpacing: 2, children: [
            for (final m in marks.take(6))
              Container(width: 7, height: 7, decoration: BoxDecoration(color: colorOf(m), shape: BoxShape.circle)),
          ]),
        ]),
      ),
    );
  }

  Widget _actionBar() => Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(24),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                child: Text(
                  '${selectedDays.length} jour(s) · ${childFilter == null ? 'tous les enfants' : kids.map((c) => c.firstName).join(', ')}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(onPressed: () => setState(selectedDays.clear), child: const Text('Annuler')),
            ]),
            Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
              _act('Absent (déduit)', Icons.event_busy_rounded, Kid.coral, 'absentDeducted'),
              _act('Absent (non déduit)', Icons.event_available_rounded, Kid.pink, 'absentNotDeducted'),
              _act('Congés', Icons.beach_access_rounded, Kid.sun, 'leave'),
              _act('Heures en plus', Icons.more_time_rounded, Kid.mint, 'extra'),
              _act('Selon planning', Icons.undo_rounded, Kid.sky, 'clear'),
            ]),
          ]),
        ),
      );

  Widget _act(String label, IconData icon, Color c, String action) => ActionChip(
        avatar: Icon(icon, size: 18, color: c),
        label: Text(label),
        onPressed: () => _apply(action),
      );
}
