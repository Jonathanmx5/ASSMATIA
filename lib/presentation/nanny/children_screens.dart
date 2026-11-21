import 'package:flutter/material.dart';

import '../../data/nanny_store.dart';
import '../../domain/engine.dart';
import '../../domain/models.dart';
import '../common.dart';
import 'contract_screens.dart';

class ChildrenTab extends StatefulWidget {
  final NannyStore store;
  const ChildrenTab({super.key, required this.store});
  @override
  State<ChildrenTab> createState() => _ChildrenTabState();
}

class _ChildrenTabState extends State<ChildrenTab> {
  bool showArchived = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final list = showArchived ? s.archivedChildren : s.activeChildren;
    return Scaffold(
      body: ListView(children: [
        SwitchListTile(
          title: const Text('Afficher les enfants archivés'),
          value: showArchived,
          onChanged: (v) => setState(() => showArchived = v),
        ),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text('Aucun enfant. Ajoutez une fiche avec le bouton +.', textAlign: TextAlign.center),
          ),
        for (final c in list)
          ListTile(
            leading: ChildDot(c.color, size: 28),
            title: Text(c.firstName),
            subtitle: Text(_subtitle(s, c)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => ChildDetailScreen(store: s, childId: c.id))),
          ),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: () => editChild(context, s, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  String _subtitle(NannyStore s, Child c) {
    final ct = s.contractOn(c.id, DateTime.now());
    if (ct == null) return 'Pas de contrat en cours';
    final t = resolveTerms(ct, DateTime.now());
    return '${t.type == ContractType.fullYear ? 'Année complète' : 'Année incomplète'} · '
        '${hrs(t.weeklyHours)}/sem · ${eur(t.monthlySalary)}/mois';
  }
}

Future<void> editChild(BuildContext context, NannyStore s, Child? c) async {
  final name = TextEditingController(text: c?.firstName ?? '');
  var color = c?.color ?? kChildColors[s.children.length % kChildColors.length];
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(c == null ? 'Nouvel enfant' : 'Modifier la fiche'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Prénom')),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final col in kChildColors)
              GestureDetector(
                onTap: () => setD(() => color = col),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Color(col),
                    shape: BoxShape.circle,
                    border: Border.all(width: 3, color: col == color ? Colors.black : Colors.transparent),
                  ),
                ),
              ),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    ),
  );
  if (ok != true || name.text.trim().isEmpty) return;
  await s.saveChild(c == null
      ? Child(id: newId(), firstName: name.text.trim(), color: color)
      : c.copyWith(firstName: name.text.trim(), color: color));
}

class ChildDetailScreen extends StatelessWidget {
  final NannyStore store;
  final String childId;
  const ChildDetailScreen({super.key, required this.store, required this.childId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = store.children[childId];
        if (c == null) return const Scaffold();
        final contracts = store.contractsOf(childId);
        return Scaffold(
          appBar: AppBar(
            title: Row(children: [ChildDot(c.color), const SizedBox(width: 8), Text(c.firstName)]),
            actions: [
              IconButton(icon: const Icon(Icons.edit), onPressed: () => editChild(context, store, c)),
              IconButton(
                tooltip: c.archived ? 'Désarchiver' : 'Archiver',
                icon: Icon(c.archived ? Icons.unarchive : Icons.archive),
                onPressed: () => store.saveChild(c.copyWith(archived: !c.archived)),
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(8), children: [
            Text('Contrats', style: Theme.of(context).textTheme.titleLarge),
            if (contracts.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Aucun contrat.')),
            for (final ct in contracts) _ContractCard(store: store, contract: ct),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Nouveau contrat'),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ContractEditScreen(store: store, childId: childId))),
            ),
            const SizedBox(height: 16),
            _SharingSection(store: store, child: c),
          ]),
        );
      },
    );
  }
}

class _ContractCard extends StatelessWidget {
  final NannyStore store;
  final Contract contract;
  const _ContractCard({required this.store, required this.contract});

  @override
  Widget build(BuildContext context) {
    final ct = contract;
    final b = ct.base;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                'Du ${fmtDate(ct.startDate)}${ct.endDate == null ? '' : ' au ${fmtDate(ct.endDate!)}'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'edit') {
                  Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ContractEditScreen(store: store, childId: ct.childId, existing: ct)));
                } else if (v == 'delete') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Supprimer ce contrat ?'),
                      content: const Text('Le contrat et ses avenants seront supprimés. Action irréversible.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
                      ],
                    ),
                  );
                  if (ok == true) await store.deleteContract(ct);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Modifier le contrat initial')),
                PopupMenuItem(value: 'delete', child: Text('Supprimer')),
              ],
            ),
          ]),
          Text('Initial : ${b.type == ContractType.fullYear ? 'année complète' : 'année incomplète (${b.weeksPerYear} sem.)'}'
              ' · ${eur(b.hourlyRate)}/h · ${hrs(b.weeklyHours)}/sem · ${eur(b.monthlySalary)}/mois'),
          const SizedBox(height: 8),
          Text('Avenants', style: Theme.of(context).textTheme.titleSmall),
          if (ct.amendments.isEmpty) const Text('Aucun avenant.', style: TextStyle(fontSize: 12)),
          for (final a in ct.amendments)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_calendar),
              title: Text('À partir du ${fmtDate(a.effectiveFrom)}${a.note.isEmpty ? '' : ' — ${a.note}'}'),
              subtitle: Builder(builder: (_) {
                final t = resolveTerms(ct, a.effectiveFrom);
                return Text('${eur(t.hourlyRate)}/h · ${hrs(t.weeklyHours)}/sem · ${eur(t.monthlySalary)}/mois');
              }),
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AmendmentEditScreen(store: store, contract: ct, existing: a))),
            ),
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un avenant'),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => AmendmentEditScreen(store: store, contract: ct))),
          ),
        ]),
      ),
    );
  }
}

class _SharingSection extends StatelessWidget {
  final NannyStore store;
  final Child child;
  const _SharingSection({required this.store, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!store.backend.supportsSharing) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Partage parents indisponible en mode local : configurez Firebase '
              '(voir README) pour activer la synchronisation et le partage.'),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Partage avec les parents (lecture seule)', style: Theme.of(context).textTheme.titleMedium),
          const Text('Les parents invités voient uniquement le planning et les récapitulatifs '
              'mensuels de cet enfant, en créant un compte « Parent » avec cet e-mail.',
              style: TextStyle(fontSize: 12)),
          for (final e in child.parentEmails)
            ListTile(
              dense: true,
              leading: const Icon(Icons.person),
              title: Text(e),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Retirer l\'accès',
                onPressed: () => store.saveChild(
                    child.copyWith(parentEmails: child.parentEmails.where((x) => x != e).toList())),
              ),
            ),
          TextButton.icon(
            icon: const Icon(Icons.person_add),
            label: const Text('Inviter un parent'),
            onPressed: () async {
              final ctl = TextEditingController();
              final email = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('E-mail du parent'),
                  content: TextField(controller: ctl, keyboardType: TextInputType.emailAddress, autofocus: true),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Autoriser')),
                  ],
                ),
              );
              final v = email?.trim().toLowerCase() ?? '';
              if (!v.contains('@') || child.parentEmails.contains(v)) return;
              await store.saveChild(child.copyWith(parentEmails: [...child.parentEmails, v]));
            },
          ),
        ]),
      ),
    );
  }
}
