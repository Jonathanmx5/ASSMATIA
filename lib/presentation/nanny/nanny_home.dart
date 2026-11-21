import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/nanny_store.dart';
import '../common.dart';
import '../update_widgets.dart';
import 'children_screens.dart';
import 'daily_tab.dart';
import 'planning_tab.dart';
import 'recap_tax_tabs.dart';
import 'settings_screen.dart';

class NannyHome extends StatefulWidget {
  final NannyStore store;
  final VoidCallback? onSignOut;
  final Future<void> Function()? onDeleteAccount;
  final Future<void> Function()? onResetPassword;
  const NannyHome({super.key, required this.store, this.onSignOut, this.onDeleteAccount, this.onResetPassword});
  @override
  State<NannyHome> createState() => _NannyHomeState();
}

class _NannyHomeState extends State<NannyHome> {
  int tab = 0;
  static const titles = ['Enfants', 'Planning', 'Suivi du jour', 'Récapitulatifs', 'Bilan fiscal'];

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    _start();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  Future<void> _start() async {
    await widget.store.load(); // synchronisation à l'ouverture
    if (!mounted || !widget.store.backend.supportsSharing) return;
    // Migration : données saisies auparavant en mode local.
    final local = await LocalFileBackend.readExisting();
    if (local == null || !mounted) return;
    final n = local[kChildren]?.length ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Données en mode local'),
        content: Text('$n fiche(s) enfant ont été saisies sur ce téléphone avant la connexion. '
            'Les transférer dans votre compte ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Plus tard')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Transférer')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.importData(local);
    final f = await LocalFileBackend.file();
    await f.rename('${f.path}.migre');
  }

  void _onStore() {
    final e = widget.store.lastError;
    if (e == null || !mounted) return;
    widget.store.clearLastError();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showError(context, e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(titles[tab]),
          actions: [
            if (!s.backend.supportsSharing)
              const Padding(padding: EdgeInsets.only(right: 4), child: Chip(label: Text('Mode local'))),
            IconButton(icon: const Icon(Icons.sync), tooltip: 'Synchroniser', onPressed: s.load),
            IconButton(
              icon: const UpdateBadgeIcon(),
              tooltip: 'Réglages',
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                          store: s, onDeleteAccount: widget.onDeleteAccount, onResetPassword: widget.onResetPassword))),
            ),
            if (widget.onSignOut != null)
              IconButton(icon: const Icon(Icons.logout), tooltip: 'Déconnexion', onPressed: widget.onSignOut),
          ],
        ),
        body: s.loading
            ? const Center(child: CircularProgressIndicator())
            : s.error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erreur : ${s.error}')))
                : switch (tab) {
                    0 => ChildrenTab(store: s),
                    1 => PlanningTab(store: s),
                    2 => DailyTab(store: s),
                    3 => RecapTab(store: s),
                    _ => TaxTab(store: s),
                  },
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.child_care), label: 'Enfants'),
            NavigationDestination(icon: Icon(Icons.calendar_view_week), label: 'Planning'),
            NavigationDestination(icon: Icon(Icons.today), label: 'Suivi'),
            NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Récaps'),
            NavigationDestination(icon: Icon(Icons.account_balance), label: 'Fiscal'),
          ],
        ),
      ),
    );
  }
}
