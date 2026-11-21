import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/nanny_store.dart';
import '../../domain/engine.dart';
import '../../domain/models.dart';
import '../common.dart';
import 'contract_screens.dart';
import '../theme.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ChildrenTab extends StatefulWidget {
  final NannyStore store;
  const ChildrenTab({super.key, required this.store});
  @override
  State<ChildrenTab> createState() => _ChildrenTabState();
}

class _ChildrenTabState extends State<ChildrenTab> {
  bool showArchived = false;

  @override
  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final list = showArchived ? s.archivedChildren : s.activeChildren;
    final today = DateTime.now();
    final here = s.activeChildren.where((c) {
      final ct = s.contractOn(c.id, today);
      return ct != null && resolveTerms(ct, today).schedule.hoursFor(today.weekday) > 0 &&
          s.kindOf(c.id, today) == DayKind.normal;
    }).length;
    final hour = today.hour;
    final hello = hour < 12 ? 'Bonjour' : hour < 18 ? 'Bon après-midi' : 'Bonsoir';
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(gradient: Kid.sunGradient, borderRadius: BorderRadius.circular(28)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$hello !', style: tt.headlineSmall?.copyWith(color: Colors.white)),
                  Text('${weekdayNames[today.weekday - 1]} ${fmtDate(today)}',
                      style: tt.titleSmall?.copyWith(color: Colors.white.withValues(alpha: .9))),
                ]),
              ),
              const Icon(Icons.wb_sunny_rounded, color: Colors.white, size: 44)
                  .animate(onPlay: (c) => loopIfEnabled(c))
                  .rotate(duration: 12.seconds),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _Pill(icon: Icons.child_care_rounded, text: '${s.activeChildren.length} enfant(s)')),
              const SizedBox(width: 8),
              Expanded(child: _Pill(icon: Icons.today_rounded, text: "$here accueilli(s) aujourd'hui")),
            ]),
          ]),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: -.1),
        SwitchListTile(
          title: const Text('Afficher les enfants archivés'),
          value: showArchived,
          onChanged: (v) => setState(() => showArchived = v),
        ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(children: [
              Icon(Icons.toys_rounded, size: 72, color: Kid.lavender.withValues(alpha: .5))
                  .animate(onPlay: (c) => loopIfEnabled(c, reverse: true))
                  .moveY(begin: -4, end: 4, duration: 1200.ms),
              const SizedBox(height: 12),
              const Text('Aucun enfant. Ajoutez une fiche avec le bouton +.', textAlign: TextAlign.center),
            ]),
          ),
        for (final (i, c) in list.indexed)
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(Kid.radius),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ChildDetailScreen(store: s, childId: c.id))),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Hero(tag: 'avatar-${c.id}', child: ChildAvatar(name: c.firstName, color: c.color, size: 54)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.firstName, style: tt.titleLarge),
                      Text(_subtitle(s, c), style: tt.bodySmall),
                    ]),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Color(c.color)),
                ]),
              ),
            ),
          ).entrance(i),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editChild(context, s, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Enfant'),
      ).animate().scale(delay: 300.ms, duration: 400.ms, curve: Curves.elasticOut),
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

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Pill({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .85), borderRadius: BorderRadius.circular(40)),
        child: Row(children: [
          Icon(icon, size: 18, color: Kid.coral),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      );
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
            title: Row(children: [Hero(tag: 'avatar-${c.id}', child: ChildAvatar(name: c.firstName, color: c.color, size: 36)), const SizedBox(width: 10), Text(c.firstName)]),
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
              onTap: () => shareInvite(child, e),
              subtitle: const Text("Toucher pour renvoyer l'invitation", style: TextStyle(fontSize: 11)),
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
              if (!context.mounted) return;
              final send = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Accès autorisé'),
                  content: Text("Envoyer l'invitation à $v (SMS, e-mail, messagerie…) ?"),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Plus tard')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Partager')),
                  ],
                ),
              );
              if (send == true) await shareInvite(child, v);
            },
          ),
        ]),
      ),
    );
  }
}

/// Message d'invitation à partager au parent.
Future<void> shareInvite(Child child, String email) => SharePlus.instance.share(ShareParams(
      subject: 'Suivi de ${child.firstName} sur ASSMATIA',
      text: "Bonjour, je vous ai donné accès au planning et aux récapitulatifs mensuels de ${child.firstName} "
          "dans l'application ASSMATIA.\n"
          "1. Installez ASSMATIA.\n"
          "2. Créez un compte avec l'adresse $email, puis confirmez-la via le lien reçu par e-mail.\n"
          "3. Choisissez « Je suis parent employeur ».\n"
          "Les informations sont en lecture seule.",
    ));
