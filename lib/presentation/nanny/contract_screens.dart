import 'package:flutter/material.dart';

import '../../data/nanny_store.dart';
import '../../domain/engine.dart';
import '../../domain/models.dart';
import '../common.dart';
import 'terms_editor.dart';

/// Message d'erreur si le planning est incohérent, sinon null.
String? scheduleError(WeeklySchedule s) {
  for (var d = 1; d <= 7; d++) {
    if (slotsOverlap(s.slotsFor(d))) return 'Tranches horaires qui se chevauchent le ${weekdayNames[d - 1].toLowerCase()}.';
  }
  return null;
}

String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

Future<DateTime?> pickDate(BuildContext context, DateTime initial) => showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime(2040),
      locale: const Locale('fr', 'FR'),
    );

/// Création / édition d'un contrat (paramètres initiaux, dates).
class ContractEditScreen extends StatefulWidget {
  final NannyStore store;
  final String childId;
  final Contract? existing;
  const ContractEditScreen({super.key, required this.store, required this.childId, this.existing});
  @override
  State<ContractEditScreen> createState() => _ContractEditScreenState();
}

class _ContractEditScreenState extends State<ContractEditScreen> {
  late DateTime start = widget.existing?.startDate ?? dayOnly(DateTime.now());
  late DateTime? end = widget.existing?.endDate;
  late ContractTerms terms = widget.existing?.base ??
      ContractTerms(
        type: ContractType.fullYear,
        hourlyRate: 4.0,
        weeksPerYear: 52,
        schedule: WeeklySchedule({
          for (var d = 1; d <= 5; d++) d: [const TimeSlot(8 * 60 + 30, 17 * 60 + 30)]
        }),
        allowances: const Allowances(mealPerDay: 4, maintenancePerDay: 3.8, maintenancePerHour: 0.42),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Nouveau contrat' : 'Contrat initial')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.existing != null && widget.existing!.amendments.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Modifier le contrat initial change tout l\'historique. '
                'Pour un changement à partir d\'une date, créez plutôt un avenant.',
                style: TextStyle(color: Colors.deepOrange)),
          ),
        ListTile(
          title: const Text('Date de début'),
          trailing: Text(fmtDate(start)),
          onTap: () async {
            final d = await pickDate(context, start);
            if (d != null) setState(() => start = d);
          },
        ),
        ListTile(
          title: const Text('Date de fin (optionnelle)'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(end == null ? '—' : fmtDate(end!)),
            if (end != null)
              IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => end = null)),
          ]),
          onTap: () async {
            final d = await pickDate(context, end ?? start);
            if (d != null) setState(() => end = d);
          },
        ),
        const Divider(),
        TermsEditor(initial: terms, netRatio: widget.store.netRatio, onChanged: (t) => terms = t),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            if (end != null && end!.isBefore(start)) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('La date de fin précède la date de début.')));
              return;
            }
            final err = scheduleError(terms.schedule);
            if (err != null) return showError(context, err);
            final c = widget.existing == null
                ? Contract(id: newId(), childId: widget.childId, startDate: start, endDate: end, base: terms)
                : widget.existing!.copyWith(startDate: start, endDate: end, clearEnd: end == null, base: terms);
            final o = widget.store.overlapping(c);
            if (o != null) {
              return showError(context,
                  'Ce contrat chevauche celui du ${fmtDate(o.startDate)}${o.endDate == null ? '' : ' au ${fmtDate(o.endDate!)}'}. '
                  'Fixez une date de fin au précédent ou utilisez un avenant.');
            }
            await widget.store.saveContract(c);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Enregistrer'),
        ),
      ]),
    );
  }
}

/// Création / édition d'un avenant daté. L'avenant enregistre les
/// paramètres complets à compter de sa date d'effet ; les périodes
/// antérieures restent calculées avec les paramètres précédents.
class AmendmentEditScreen extends StatefulWidget {
  final NannyStore store;
  final Contract contract;
  final Amendment? existing;
  const AmendmentEditScreen({super.key, required this.store, required this.contract, this.existing});
  @override
  State<AmendmentEditScreen> createState() => _AmendmentEditScreenState();
}

class _AmendmentEditScreenState extends State<AmendmentEditScreen> {
  late DateTime from = widget.existing?.effectiveFrom ?? dayOnly(DateTime.now());
  late final note = TextEditingController(text: widget.existing?.note ?? '');
  late ContractTerms terms = _termsBefore(from);
  Key editorKey = UniqueKey();

  ContractTerms _termsBefore(DateTime d) {
    if (widget.existing != null) {
      // Paramètres en vigueur avec cet avenant.
      final others = widget.contract.amendments.where((a) => a.id != widget.existing!.id).toList();
      return resolveTerms(widget.contract.copyWith(amendments: others), d).apply(widget.existing!);
    }
    return resolveTerms(widget.contract, d);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Nouvel avenant' : 'Avenant')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ListTile(
          title: const Text('Date d\'effet'),
          trailing: Text(fmtDate(from)),
          onTap: () async {
            final d = await pickDate(context, from);
            if (d == null) return;
            setState(() {
              from = d;
              if (widget.existing == null) {
                terms = _termsBefore(d);
                editorKey = UniqueKey();
              }
            });
          },
        ),
        TextField(
            controller: note,
            decoration: const InputDecoration(labelText: 'Objet de l\'avenant', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TermsEditor(key: editorKey, initial: terms, netRatio: widget.store.netRatio, onChanged: (t) => terms = t),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            final err = scheduleError(terms.schedule);
            if (err != null) return showError(context, err);
            if (!widget.contract.isActiveOn(from)) {
              return showError(context, "La date d'effet doit être comprise dans la durée du contrat.");
            }
            final a = Amendment(
              id: widget.existing?.id ?? newId(),
              effectiveFrom: from,
              note: note.text.trim(),
              type: terms.type,
              hourlyRate: terms.hourlyRate,
              weeksPerYear: terms.weeksPerYear,
              schedule: terms.schedule,
              allowances: terms.allowances,
            );
            final list = [...widget.contract.amendments.where((x) => x.id != a.id), a]
              ..sort((x, y) => x.effectiveFrom.compareTo(y.effectiveFrom));
            await widget.store.saveContract(widget.contract.copyWith(amendments: list));
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Enregistrer l\'avenant'),
        ),
        if (widget.existing != null)
          TextButton(
            onPressed: () async {
              final list = widget.contract.amendments.where((x) => x.id != widget.existing!.id).toList();
              await widget.store.saveContract(widget.contract.copyWith(amendments: list));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Supprimer cet avenant', style: TextStyle(color: Colors.red)),
          ),
      ]),
    );
  }
}
