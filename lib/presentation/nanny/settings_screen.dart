import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/backend.dart';
import '../../data/nanny_store.dart';
import '../../domain/models.dart';
import '../common.dart';
import 'contract_screens.dart';

/// Congés, paramètres, sauvegarde et compte.
class SettingsScreen extends StatelessWidget {
  final NannyStore store;
  final Future<void> Function()? onDeleteAccount;
  final Future<void> Function()? onResetPassword;
  const SettingsScreen({super.key, required this.store, this.onDeleteAccount, this.onResetPassword});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Réglages')),
        body: ListView(children: [
          const _Header('Congés et périodes sans accueil'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
                "Vos congés, les semaines non programmées (année incomplète) ou les fermetures : aucun accueil, "
                "aucune indemnité, aucune déduction, et pas d'abattement fiscal ces jours-là. "
                'Les jours fériés sont gérés automatiquement.',
                style: TextStyle(fontSize: 12)),
          ),
          for (final p in store.leaves.values.toList()..sort((a, b) => a.from.compareTo(b.from)))
            ListTile(
              leading: const Icon(Icons.beach_access),
              title: Text('${fmtDate(p.from)} → ${fmtDate(p.to)}${p.label.isEmpty ? '' : ' · ${p.label}'}'),
              subtitle: Text(p.childIds.isEmpty
                  ? 'Tous les enfants'
                  : p.childIds.map((id) => store.children[id]?.firstName ?? '?').join(', ')),
              onTap: () => _editLeave(context, p),
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => store.deleteLeave(p)),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Ajouter une période'),
            onTap: () => _editLeave(context, null),
          ),
          const _Header('Calculs'),
          ListTile(
            leading: const Icon(Icons.percent),
            title: const Text('Taux de conversion brut → net'),
            subtitle: const Text('Part du brut versée en net (≈ 78 % pour une assistante maternelle). '
                'Sert au net estimé et aux revenus imposables.'),
            trailing: Text('${hoursFmt.format(store.netRatio * 100)} %'),
            onTap: () => _editRatio(context),
          ),
          const _Header('Sauvegarde'),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Exporter mes données (JSON)'),
            subtitle: const Text('Fichier à conserver ou à transférer'),
            onTap: () => _export(context),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Importer une sauvegarde'),
            subtitle: const Text('Fusionne le fichier avec vos données actuelles'),
            onTap: () => _import(context),
          ),
          if (onResetPassword != null || onDeleteAccount != null) const _Header('Compte'),
          if (onResetPassword != null)
            ListTile(
              leading: const Icon(Icons.password),
              title: const Text('Changer de mot de passe'),
              subtitle: const Text('Un lien vous est envoyé par e-mail'),
              onTap: () async {
                await onResetPassword!();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('E-mail envoyé.')));
                }
              },
            ),
          if (onDeleteAccount != null)
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Supprimer mon compte et mes données', style: TextStyle(color: Colors.red)),
              onTap: () => _deleteAccount(context),
            ),
          const Disclaimer(),
        ]),
      ),
    );
  }

  Future<void> _editLeave(BuildContext context, LeavePeriod? p) async {
    var from = p?.from ?? dayOnly(DateTime.now());
    var to = p?.to ?? from.add(const Duration(days: 6));
    final label = TextEditingController(text: p?.label ?? 'Congés');
    final selected = {...?p?.childIds};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Période sans accueil'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: label, decoration: const InputDecoration(labelText: 'Libellé')),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Du'),
                trailing: Text(fmtDate(from)),
                onTap: () async {
                  final d = await pickDate(ctx, from);
                  if (d != null) setD(() => from = d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Au'),
                trailing: Text(fmtDate(to)),
                onTap: () async {
                  final d = await pickDate(ctx, to);
                  if (d != null) setD(() => to = d);
                },
              ),
              const Align(alignment: Alignment.centerLeft, child: Text('Enfants concernés (aucun = tous)')),
              for (final c in store.activeChildren)
                CheckboxListTile(
                  dense: true,
                  value: selected.contains(c.id),
                  title: Text(c.firstName),
                  onChanged: (v) => setD(() => v == true ? selected.add(c.id) : selected.remove(c.id)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (to.isBefore(from)) {
      if (context.mounted) showError(context, 'La date de fin précède la date de début.');
      return;
    }
    await store.saveLeave(LeavePeriod(
        id: p?.id ?? newId(), from: from, to: to, label: label.text.trim(), childIds: selected.toList()));
  }

  Future<void> _editRatio(BuildContext context) async {
    final ctl = TextEditingController(text: hoursFmt.format(store.netRatio * 100));
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Taux brut → net (%)'),
        content: TextField(controller: ctl, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('OK')),
        ],
      ),
    );
    final n = v == null ? null : parseNum(v);
    if (n != null && n > 0 && n <= 100) await store.setNetRatio(n / 100);
  }

  Future<void> _export(BuildContext context) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/assmatia_${dateKey(DateTime.now())}.json');
    await f.writeAsString(store.exportJson());
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], subject: 'Sauvegarde ASSMATIA'));
  }

  Future<void> _import(BuildContext context) async {
    try {
      final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      final path = res.isEmpty ? null : res.single.path;
      if (path == null) return;
      final raw = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      final data = LocalFileBackend.decode(jsonEncode(raw['data'] ?? raw));
      await store.importData(data);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${data[kChildren]?.length ?? 0} fiche(s) enfant importée(s).')));
      }
    } catch (e) {
      if (context.mounted) showError(context, 'Fichier invalide : $e');
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer définitivement ?'),
        content: const Text('Toutes vos données (enfants, contrats, suivis, récapitulatifs partagés) et votre compte '
            'seront supprimés. Action irréversible : exportez une sauvegarde avant si besoin.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await store.deleteEverything();
      await onDeleteAccount!();
      if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (context.mounted) showError(context, 'Suppression impossible : $e. Reconnectez-vous puis réessayez.');
    }
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
