import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../common.dart';

/// Éditeur de planning hebdomadaire (plusieurs tranches par jour).
class ScheduleEditor extends StatelessWidget {
  final WeeklySchedule value;
  final ValueChanged<WeeklySchedule> onChanged;
  const ScheduleEditor({super.key, required this.value, required this.onChanged});

  void _set(int day, List<TimeSlot> slots) {
    final m = Map<int, List<TimeSlot>>.from(value.days);
    if (slots.isEmpty) {
      m.remove(day);
    } else {
      m[day] = slots;
    }
    onChanged(WeeklySchedule(m));
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (var d = 1; d <= 7; d++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 44,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(weekdayShort[d - 1]),
                )),
            Expanded(
              child: Wrap(spacing: 4, runSpacing: 4, children: [
                for (var i = 0; i < value.slotsFor(d).length; i++)
                  InputChip(
                    label: Text('${value.slotsFor(d)[i]}'),
                    onPressed: () async {
                      final s = value.slotsFor(d)[i];
                      final a = await pickTime(context, s.startMin);
                      if (a == null || !context.mounted) return;
                      final b = await pickTime(context, s.endMin);
                      if (b == null || b <= a) return;
                      final l = [...value.slotsFor(d)];
                      l[i] = TimeSlot(a, b);
                      _set(d, l);
                    },
                    onDeleted: () {
                      final l = [...value.slotsFor(d)]..removeAt(i);
                      _set(d, l);
                    },
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(value.slotsFor(d).isEmpty ? 'Ajouter' : 'Tranche'),
                  onPressed: () {
                    final l = [...value.slotsFor(d)];
                    final start = l.isEmpty ? 8 * 60 : l.last.endMin + 60;
                    l.add(TimeSlot(start.clamp(0, 22 * 60),
                        (start + (l.isEmpty ? 9 * 60 : 60)).clamp(60, 23 * 60 + 59)));
                    _set(d, l);
                  },
                ),
              ]),
            ),
            SizedBox(
                width: 48,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(value.hoursFor(d) > 0 ? hrs(value.hoursFor(d)) : '',
                      textAlign: TextAlign.right),
                )),
          ]),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: Text('Total : ${hrs(value.weeklyHours)} / semaine',
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    ]);
  }
}

/// Éditeur des paramètres d'un contrat (ou d'un avenant).
class TermsEditor extends StatefulWidget {
  final ContractTerms initial;
  final ValueChanged<ContractTerms> onChanged;
  const TermsEditor({super.key, required this.initial, required this.onChanged});
  @override
  State<TermsEditor> createState() => _TermsEditorState();
}

class _TermsEditorState extends State<TermsEditor> {
  late ContractType type = widget.initial.type;
  late WeeklySchedule schedule = widget.initial.schedule;
  late final rate = TextEditingController(text: '${widget.initial.hourlyRate}');
  late final weeks = TextEditingController(text: '${widget.initial.weeksPerYear}');
  late final meal = TextEditingController(text: '${widget.initial.allowances.mealPerDay}');
  late final mDay = TextEditingController(text: '${widget.initial.allowances.maintenancePerDay}');
  late final mHour = TextEditingController(text: '${widget.initial.allowances.maintenancePerHour}');

  ContractTerms get current => ContractTerms(
        type: type,
        hourlyRate: parseNum(rate.text) ?? 0,
        weeksPerYear: type == ContractType.fullYear ? 52 : (int.tryParse(weeks.text) ?? 0),
        schedule: schedule,
        allowances: Allowances(
          mealPerDay: parseNum(meal.text) ?? 0,
          maintenancePerDay: parseNum(mDay.text) ?? 0,
          maintenancePerHour: parseNum(mHour.text) ?? 0,
        ),
      );

  void _emit() => setState(() => widget.onChanged(current));

  Widget _num(TextEditingController c, String label, {String? suffix}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, suffixText: suffix, border: const OutlineInputBorder()),
          onChanged: (_) => _emit(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = current;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<ContractType>(
        segments: const [
          ButtonSegment(value: ContractType.fullYear, label: Text('Année complète')),
          ButtonSegment(value: ContractType.partialYear, label: Text('Année incomplète')),
        ],
        selected: {type},
        onSelectionChanged: (s) {
          type = s.first;
          _emit();
        },
      ),
      const SizedBox(height: 8),
      _num(rate, 'Taux horaire brut', suffix: '€/h'),
      if (type == ContractType.partialYear)
        _num(weeks, 'Semaines programmées par an', suffix: 'sem.'),
      const SizedBox(height: 8),
      Text('Planning hebdomadaire', style: Theme.of(context).textTheme.titleSmall),
      ScheduleEditor(
          value: schedule,
          onChanged: (s) {
            schedule = s;
            _emit();
          }),
      const SizedBox(height: 8),
      Text('Indemnités', style: Theme.of(context).textTheme.titleSmall),
      _num(meal, 'Repas par jour d\'accueil', suffix: '€'),
      _num(mDay, 'Entretien : forfait minimum par jour', suffix: '€'),
      _num(mHour, 'Entretien : montant par heure d\'accueil', suffix: '€/h'),
      const Text('Entretien du jour = max(forfait, montant horaire × heures).',
          style: TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Line('Heures mensualisées', hrs(double.parse(t.monthlyHours.toStringAsFixed(2)))),
            Line('Salaire mensualisé brut', eur(t.monthlySalary), bold: true),
          ]),
        ),
      ),
    ]);
  }
}
