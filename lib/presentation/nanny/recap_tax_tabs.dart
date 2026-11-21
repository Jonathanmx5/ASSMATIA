import 'package:flutter/material.dart';

import '../../data/nanny_store.dart';
import '../../domain/engine.dart';
import '../../domain/models.dart';
import '../common.dart';

class RecapTab extends StatefulWidget {
  final NannyStore store;
  const RecapTab({super.key, required this.store});
  @override
  State<RecapTab> createState() => _RecapTabState();
}

class _RecapTabState extends State<RecapTab> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final cards = <Widget>[];
    for (final c in s.children.values) {
      final sm = s.summary(c.id, month.year, month.month);
      if (sm == null) continue;
      cards.add(SummaryCard(title: c.firstName, color: c.color, s: sm.toJson()));
    }
    return Column(children: [
      Row(children: [
        IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => month = DateTime(month.year, month.month - 1))),
        Expanded(child: Center(child: Text(monthLabel(month.year, month.month), style: Theme.of(context).textTheme.titleMedium))),
        IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => month = DateTime(month.year, month.month + 1))),
      ]),
      Expanded(
        child: ListView(children: [
          const Disclaimer(compact: true),
          if (cards.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Text('Aucun contrat sur ce mois.')),
          ...cards,
        ]),
      ),
    ]);
  }
}

/// Bilan fiscal annuel (réservé à l'assistante maternelle).
class TaxTab extends StatefulWidget {
  final NannyStore store;
  const TaxTab({super.key, required this.store});
  @override
  State<TaxTab> createState() => _TaxTabState();
}

class _TaxTabState extends State<TaxTab> {
  int year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final AnnualTaxReport r = s.annualTax(year);
    final override = s.incomeOverrides[year];
    return ListView(padding: const EdgeInsets.all(8), children: [
      Row(children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => year--)),
        Expanded(child: Center(child: Text('Année civile $year', style: Theme.of(context).textTheme.titleMedium))),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => year++)),
      ]),
      const Disclaimer(),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('SMIC horaire de référence'),
              subtitle: const Text('Barème configurable par année'),
              trailing: Text(eur(r.smic)),
              onTap: () => _editSmic(context, s),
            ),
            Line('Abattement par journée ≥ 8 h (3 × SMIC)', eur(round2(3 * r.smic))),
            Line('Journées d\'accueil (tous enfants)', '${r.careDays}'),
            const Divider(),
            for (final e in r.abatementByChild.entries)
              Line('Abattement ${s.children[e.key]?.firstName ?? '?'}', eur(e.value)),
            Line('Abattement total', eur(r.totalAbatement), bold: true),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Revenus imposables annuels'),
              subtitle: Text(override == null
                  ? 'Somme des salaires nets calculés (hors indemnités). Touchez pour saisir.'
                  : 'Montant saisi manuellement. Touchez pour modifier.'),
              trailing: Text(eur(r.taxableIncome)),
              onTap: () => _editIncome(context, s, r),
            ),
            Line('Revenu net imposable', eur(r.netTaxable), bold: true),
          ]),
        ),
      ),
    ]);
  }

  Future<void> _editSmic(BuildContext context, NannyStore s) async {
    final ctl = TextEditingController(text: '${s.scaleFor(year).smicHourly}');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('SMIC horaire $year'),
        content: TextField(controller: ctl, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('OK')),
        ],
      ),
    );
    final n = v == null ? null : parseNum(v);
    if (n != null && n > 0) await s.saveTaxScale(TaxScale(year, n));
  }

  Future<void> _editIncome(BuildContext context, NannyStore s, AnnualTaxReport r) async {
    final ctl = TextEditingController(text: s.incomeOverrides[year]?.toString() ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revenus imposables (salaires hors indemnités)'),
        content: TextField(
          controller: ctl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: 'Vide = calcul automatique'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('OK')),
        ],
      ),
    );
    if (v == null) return;
    await s.setIncomeOverride(year, parseNum(v));
  }
}
