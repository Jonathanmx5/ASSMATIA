import 'package:flutter/material.dart';

import '../data/updater.dart';

/// Engrenage avec pastille quand une mise à jour est disponible.
class UpdateBadgeIcon extends StatelessWidget {
  const UpdateBadgeIcon({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Updater.instance,
        builder: (_, _) => Badge(
          isLabelVisible: Updater.instance.hasUpdate,
          smallSize: 10,
          child: const Icon(Icons.settings),
        ),
      );
}

/// Bouton engrenage ouvrant le panneau « Application » (version, mise à jour).
class UpdateGearButton extends StatelessWidget {
  const UpdateGearButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Application et mises à jour',
        icon: const UpdateBadgeIcon(),
        onPressed: () => showUpdateSheet(context),
      );
}

void showUpdateSheet(BuildContext context) {
  final u = Updater.instance;
  if (u.state != UpdateState.downloading) u.check();
  showModalBottomSheet(
    context: context,
    builder: (_) => const Padding(padding: EdgeInsets.all(16), child: UpdatePanel()),
  );
}

/// Contenu réutilisable (panneau et écran Réglages).
class UpdatePanel extends StatelessWidget {
  const UpdatePanel({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Updater.instance,
        builder: (context, _) {
          final u = Updater.instance;
          final l = u.latest;
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('ASSMATIA', style: Theme.of(context).textTheme.titleLarge),
            Text('Version installée : ${u.currentVersion.isEmpty ? '…' : '${u.currentVersion} (${u.currentBuild})'}'),
            const SizedBox(height: 12),
            switch (u.state) {
              UpdateState.checking || UpdateState.idle => const Row(children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Text('Recherche de mise à jour…'),
                ]),
              UpdateState.upToDate => const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.check_circle, color: Colors.green),
                  title: Text("L'application est à jour."),
                ),
              UpdateState.downloading => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Téléchargement de la version ${l?.version}…'),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: u.progress > 0 ? u.progress : null),
                ]),
              UpdateState.available => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Nouvelle version disponible : ${l!.version}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (l.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(l.notes)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.system_update),
                    label: const Text('Mettre à jour'),
                    onPressed: u.install,
                  ),
                ]),
              UpdateState.error => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.error_outline, color: Colors.red),
                  title: Text(u.message ?? 'Erreur'),
                ),
            },
            if (u.message != null && u.state == UpdateState.available)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(u.message!)),
            if (u.state == UpdateState.upToDate || u.state == UpdateState.error)
              TextButton(onPressed: u.check, child: const Text('Vérifier à nouveau')),
          ]);
        },
      );
}
