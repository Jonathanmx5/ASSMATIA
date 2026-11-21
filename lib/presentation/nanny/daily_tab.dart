import 'package:flutter/material.dart';

import '../../data/nanny_store.dart';
import '../../domain/engine.dart';
import '../../domain/models.dart';
import '../common.dart';
import 'contract_screens.dart';

/// Suivi quotidien : présence, horaires effectifs, absences, indemnités.
class DailyTab extends StatefulWidget {
  final NannyStore store;
  const DailyTab({super.key, required this.store});
  @override
  State<DailyTab> createState() => _DailyTabState();
}

String statusLabel(DayStatus s) => switch (s) {
      DayStatus.present => 'Présent',
      DayStatus.absentDeducted => 'Absent (déduit)',
      DayStatus.absentNotDeducted => 'Absent (non déduit)',
      DayStatus.notScheduled => 'Pas d\'accueil',
    };

class _DailyTabState extends State<DailyTab> {
  DateTime day = dayOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final kids = s.activeChildren.where((c) => s.contractOn(c.id, day) != null).toList();
    return Column(children: [
      Row(children: [
        IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => day = day.subtract(const Duration(days: 1)))),
        Expanded(
          child: TextButton(
            onPressed: () async {
              final d = await pickDate(context, day);
              if (d != null) setState(() => day = d);
            },
            child: Text('${weekdayNames[day.weekday - 1]} ${fmtDate(day)}'),
          ),
        ),
        IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => day = day.add(const Duration(days: 1)))),
      ]),
      Expanded(
        child: ListView(children: [
          if (kids.isEmpty)
            const Padding(padding: EdgeInsets.all(32), child: Text('Aucun contrat actif ce jour.')),
          for (final c in kids) _card(context, s, c),
        ]),
      ),
    ]);
  }

  Widget _card(BuildContext context, NannyStore s, Child c) {
    final ct = s.contractOn(c.id, day)!;
    final t = resolveTerms(ct, day);
    final log = s.logOf(c.id, day);
    final r = computeDay(t, day, log);
    return Card(
      child: ListTile(
        leading: ChildDot(c.color, size: 24),
        title: Text('${c.firstName} — ${log == null ? 'Selon planning' : statusLabel(log.status)}'),
        subtitle: Text([
          'Prévu ${hrs(r.plannedHours)}',
          'Effectué ${hrs(r.workedHours)}',
          if (r.absenceDeductedHours > 0) 'Absence déduite ${hrs(r.absenceDeductedHours)}',
          'Repas ${eur(r.meal)} · Entretien ${eur(round2(r.maintenance))}',
          if (log?.note.isNotEmpty ?? false) log!.note,
        ].join('\n')),
        isThreeLine: true,
        trailing: const Icon(Icons.edit),
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => _LogEditor(store: s, child: c, terms: t, day: day, existing: log),
        ),
      ),
    );
  }
}

class _LogEditor extends StatefulWidget {
  final NannyStore store;
  final Child child;
  final ContractTerms terms;
  final DateTime day;
  final DailyLog? existing;
  const _LogEditor({required this.store, required this.child, required this.terms, required this.day, this.existing});
  @override
  State<_LogEditor> createState() => _LogEditorState();
}

class _LogEditorState extends State<_LogEditor> {
  late DayStatus status = widget.existing?.status ?? DayStatus.present;
  late List<TimeSlot> slots = widget.existing?.actualSlots ?? widget.terms.schedule.slotsFor(widget.day.weekday);
  late final absence = TextEditingController(
      text: hoursFmt.format(widget.existing?.absenceHours ?? widget.terms.schedule.hoursFor(widget.day.weekday)));
  late final meal = TextEditingController(text: widget.existing?.mealOverride?.toString() ?? '');
  late final maint = TextEditingController(text: widget.existing?.maintenanceOverride?.toString() ?? '');
  late final note = TextEditingController(text: widget.existing?.note ?? '');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('${widget.child.firstName} — ${fmtDate(widget.day)}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final st in DayStatus.values)
              ChoiceChip(label: Text(statusLabel(st)), selected: status == st, onSelected: (_) => setState(() => status = st)),
          ]),
          const SizedBox(height: 8),
          if (status == DayStatus.present) ...[
            const Text('Horaires effectifs'),
            Wrap(spacing: 4, children: [
              for (var i = 0; i < slots.length; i++)
                InputChip(
                  label: Text('${slots[i]}'),
                  onPressed: () async {
                    final a = await pickTime(context, slots[i].startMin);
                    if (a == null || !context.mounted) return;
                    final b = await pickTime(context, slots[i].endMin);
                    if (b == null || b <= a) return;
                    setState(() => slots = [...slots]..[i] = TimeSlot(a, b));
                  },
                  onDeleted: () => setState(() => slots = [...slots]..removeAt(i)),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('Tranche'),
                onPressed: () => setState(() => slots = [...slots, const TimeSlot(8 * 60, 17 * 60)]),
              ),
            ]),
            TextField(
              controller: meal,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: 'Indemnité repas (vide = ${eur(widget.terms.allowances.mealPerDay)})'),
            ),
            TextField(
              controller: maint,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Indemnité entretien (vide = calcul automatique)'),
            ),
          ],
          if (status == DayStatus.absentDeducted)
            TextField(
              controller: absence,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Heures d\'absence prévues au planning', suffixText: 'h'),
            ),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
          const SizedBox(height: 12),
          Row(children: [
            if (widget.existing != null)
              TextButton(
                onPressed: () async {
                  await widget.store.deleteLog(widget.existing!);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Revenir au planning'),
              ),
            const Spacer(),
            FilledButton(
              onPressed: () async {
                final planned = widget.terms.schedule.slotsFor(widget.day.weekday);
                final same = slots.length == planned.length &&
                    List.generate(slots.length, (i) => slots[i].startMin == planned[i].startMin && slots[i].endMin == planned[i].endMin)
                        .every((x) => x);
                await widget.store.saveLog(DailyLog(
                  childId: widget.child.id,
                  date: widget.day,
                  status: status,
                  actualSlots: status == DayStatus.present && !same ? slots : null,
                  absenceHours: status == DayStatus.absentDeducted ? (parseNum(absence.text) ?? 0) : 0,
                  mealOverride: status == DayStatus.present ? parseNum(meal.text) : null,
                  maintenanceOverride: status == DayStatus.present ? parseNum(maint.text) : null,
                  note: note.text.trim(),
                ));
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Enregistrer'),
            ),
          ]),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}
