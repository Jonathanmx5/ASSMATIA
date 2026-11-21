import 'package:flutter/material.dart';

import '../../data/nanny_store.dart';
import '../../domain/engine.dart';
import '../../domain/models.dart';
import '../common.dart';
import '../theme.dart';
import 'daily_tab.dart';

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
      final locked = s.isLocked(c.id, month.year, month.month);
      final proj = sm.provisional && !locked ? s.projectedSummary(c.id, month.year, month.month) : null;
      cards.add(SummaryCard(title: c.firstName, color: c.color, s: sm.toJson(), footer: [
        if (proj != null)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Kid.mint.withValues(alpha: .15), borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.auto_graph_rounded, color: Kid.mint),
                SizedBox(width: 6),
                Text('Simulation fin de mois', style: TextStyle(fontWeight: FontWeight.w800)),
              ]),
              const Text('Si la suite du mois se déroule selon le planning (absences et retards déjà notés compris).',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              Line('Salaire brut prévu', eur(proj.grossSalary)),
              Line('Salaire net prévu', eur(proj.netSalary)),
              Line('Indemnités prévues', eur(proj.allowancesTotal)),
              Line('Total prévu à verser', eur(proj.totalToPay), bold: true),
            ]),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.list_alt),
            label: const Text('Détail par jour'),
            onPressed: () => _details(context, s, c),
          ),
          if (locked)
            TextButton.icon(
              icon: const Icon(Icons.lock_open),
              label: const Text('Déverrouiller'),
              onPressed: () => s.unlockMonth(c.id, month.year, month.month),
            )
          else
            FilledButton.tonalIcon(
              icon: const Icon(Icons.lock),
              label: const Text('Valider le mois'),
              onPressed: () => _confirmLock(context, s, c),
            ),
        ]),
      ]));
    }
    return Column(children: [
      Row(children: [
        IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => month = DateTime(month.year, month.month - 1))),
        Expanded(
            child: Center(
                child: Text(monthLabel(month.year, month.month), style: Theme.of(context).textTheme.titleMedium))),
        IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => month = DateTime(month.year, month.month + 1))),
      ]),
      Expanded(
        child: ListView(children: [
          const Disclaimer(compact: true),
          if (cards.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Text('Aucun contrat sur ce mois.')),
          ...cards,
          if (month.month == 5 || month.month == 6) ..._paidLeaveCards(context, s),
        ]),
      ),
    ]);
  }

  /// Estimation des congés payés en fin de période de référence (mai/juin).
  List<Widget> _paidLeaveCards(BuildContext context, NannyStore s) {
    final refEnd = month.year;
    final out = <Widget>[];
    for (final c in s.children.values) {
      for (final ct in s.contractsOf(c.id)) {
        final p = s.paidLeave(ct, refEnd);
        if (p == null) continue;
        out.add(PaidLeaveCard(child: c, p: p));
      }
    }
    return out;
  }

  Future<void> _confirmLock(BuildContext context, NannyStore s, Child c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Valider ${monthLabel(month.year, month.month)} pour ${c.firstName} ?'),
        content: const Text('Le récapitulatif est figé : un avenant ou une saisie ultérieure ne le modifiera plus. '
            'Vous pourrez le déverrouiller.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Valider')),
        ],
      ),
    );
    if (ok == true) await s.lockMonth(c.id, month.year, month.month);
  }

  void _details(BuildContext context, NannyStore s, Child c) {
    final details = <DayResult>[];
    s.summary(c.id, month.year, month.month, details: details);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .8,
        builder: (_, ctl) => ListView(controller: ctl, children: [
          ListTile(title: Text('${c.firstName} — ${monthLabel(month.year, month.month)}', style: Theme.of(context).textTheme.titleLarge)),
          for (final r in details.where((r) => r.plannedHours > 0 || r.workedHours > 0))
            ListTile(
              dense: true,
              title: Text('${weekdayShort[r.date.weekday - 1]} ${fmtDate(r.date)}'
                  '${s.logOf(c.id, r.date) != null ? ' — ${statusLabel(s.logOf(c.id, r.date)!.status)}' : ' — ${kindLabel(r.kind)}'}'),
              subtitle: Text('Prévu ${hrs(r.plannedHours)} · Effectué ${hrs(r.workedHours)}'
                  '${r.absenceDeductedHours > 0 ? ' · Déduit ${hrs(r.absenceDeductedHours)}' : ''}'),
              trailing: Text('${eur(r.meal)}\n${eur(round2(r.maintenance))}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11)),
            ),
        ]),
      ),
    );
  }
}

class PaidLeaveCard extends StatelessWidget {
  final Child child;
  final PaidLeaveEstimate p;
  const PaidLeaveCard({super.key, required this.child, required this.p});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ChildDot(child.color),
              const SizedBox(width: 8),
              Text('Congés payés — ${child.firstName}', style: Theme.of(context).textTheme.titleMedium),
            ]),
            Text('Période ${fmtDate(p.refStart)} → ${fmtDate(p.refEnd)} (estimation)', style: const TextStyle(fontSize: 12)),
            const Divider(),
            Line("Mois d'accueil", '${p.monthsWorked}'),
            Line('Jours ouvrables acquis', '${p.daysAcquired}'),
            Line('Salaires bruts de la période', eur(p.grossReference)),
            Line('Méthode du 10 %', eur(p.tenPercent)),
            Line('Maintien de salaire', eur(p.maintien)),
            Line('Montant retenu (plus favorable)', eur(p.retained), bold: true),
            Line(p.includedInMonthly ? 'Complément éventuel (année complète)' : 'À verser en plus (année incomplète)',
                eur(p.toPayExtra), bold: true),
          ]),
        ),
      );
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
      if (r.partial)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text("Année en cours : bilan arrêté à aujourd'hui (jours à venir non comptés).",
              style: TextStyle(color: Colors.deepOrange)),
        ),
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
            Line("Journées d'accueil effectives (tous enfants)", '${r.careDays}'),
            const Text('Hors jours fériés, congés et jours à venir.', style: TextStyle(fontSize: 11)),
            const Divider(),
            for (final e in r.abatementByChild.entries)
              Line('Abattement ${s.children[e.key]?.firstName ?? '?'}', eur(e.value)),
            Line('Abattement total', eur(r.totalAbatement), bold: true),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Revenus imposables annuels (nets)'),
              subtitle: Text(override == null
                  ? 'Salaires nets estimés (brut × ${hoursFmt.format(s.netRatio * 100)} %), hors indemnités. '
                      'Remplacez par le montant Pajemploi en touchant ici.'
                  : 'Montant saisi manuellement. Touchez pour modifier.'),
              trailing: Text(eur(r.taxableIncome)),
              onTap: () => _editIncome(context, s),
            ),
            Line('Revenu net imposable', eur(r.netTaxable), bold: true),
          ]),
        ),
      ),
    ]);
  }

  Future<String?> _ask(BuildContext context, String title, String initial, {String? hint}) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: ctl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _editSmic(BuildContext context, NannyStore s) async {
    final v = await _ask(context, 'SMIC horaire $year', '${s.scaleFor(year).smicHourly}');
    final n = v == null ? null : parseNum(v);
    if (n != null && n > 0) await s.saveTaxScale(TaxScale(year, n));
  }

  Future<void> _editIncome(BuildContext context, NannyStore s) async {
    final v = await _ask(context, 'Revenus imposables nets (hors indemnités)', s.incomeOverrides[year]?.toString() ?? '',
        hint: 'Vide = calcul automatique');
    if (v == null) return;
    await s.setIncomeOverride(year, parseNum(v));
  }
}
