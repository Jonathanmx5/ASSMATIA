import 'package:flutter/material.dart';

import '../../data/nanny_store.dart';
import 'children_screens.dart';
import 'daily_tab.dart';
import 'planning_tab.dart';
import 'recap_tax_tabs.dart';

class NannyHome extends StatefulWidget {
  final NannyStore store;
  final VoidCallback? onSignOut;
  const NannyHome({super.key, required this.store, this.onSignOut});
  @override
  State<NannyHome> createState() => _NannyHomeState();
}

class _NannyHomeState extends State<NannyHome> {
  int tab = 0;
  static const titles = ['Enfants', 'Planning', 'Suivi du jour', 'Récapitulatifs', 'Bilan fiscal'];

  @override
  void initState() {
    super.initState();
    widget.store.load(); // synchronisation à l'ouverture
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
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Chip(label: Text('Mode local')),
              ),
            IconButton(icon: const Icon(Icons.sync), tooltip: 'Synchroniser', onPressed: s.load),
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
