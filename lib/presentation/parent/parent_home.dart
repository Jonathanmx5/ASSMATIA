import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../domain/models.dart';
import '../common.dart';
import '../update_widgets.dart';

/// Espace parent : lecture seule du planning et des récapitulatifs mensuels
/// des enfants auxquels le parent est rattaché. Rechargé à chaque ouverture.
class ParentHome extends StatefulWidget {
  final ParentReader reader;
  final VoidCallback onSignOut;
  final Future<void> Function()? onDeleteAccount;
  const ParentHome({super.key, required this.reader, required this.onSignOut, this.onDeleteAccount});
  @override
  State<ParentHome> createState() => _ParentHomeState();
}

class _ParentHomeState extends State<ParentHome> {
  late Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>, List<AbsenceRequest>)> data = _load();
  List<Map<String, dynamic>> _plannings = [];
  List<AbsenceRequest> _requests = [];

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>, List<AbsenceRequest>)> _load() async {
    final p = await widget.reader.plannings();
    _plannings = p;
    List<AbsenceRequest> r = [];
    try {
      r = (await widget.reader.myRequests()).map(AbsenceRequest.fromJson).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      // Liste des demandes indisponible (hors ligne) : on garde la dernière connue.
      r = _requests;
    }
    if (mounted) setState(() => _requests = r);
    return (p, await widget.reader.summaries(), r);
  }

  Future<void> _newRequest() async {
    if (_plannings.isEmpty) return;
    var child = _plannings.first;
    var kind = RequestKind.absence;
    var from = dayOnly(DateTime.now());
    var to = from;
    final hours = TextEditingController(text: '1');
    final msg = TextEditingController();
    Future<DateTime?> pick(BuildContext ctx, DateTime d) => showDatePicker(
        context: ctx, initialDate: d, firstDate: addDays(DateTime.now(), -60), lastDate: DateTime(DateTime.now().year + 2),
        locale: const Locale('fr', 'FR'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Prévenir mon assistante maternelle'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_plannings.length > 1)
                DropdownButton<Map<String, dynamic>>(
                  value: child,
                  isExpanded: true,
                  items: [for (final p in _plannings) DropdownMenuItem(value: p, child: Text('${p['firstName']}'))],
                  onChanged: (v) => setD(() => child = v!),
                ),
              SegmentedButton<RequestKind>(
                segments: const [
                  ButtonSegment(value: RequestKind.absence, label: Text('Absence'), icon: Icon(Icons.event_busy_rounded)),
                  ButtonSegment(value: RequestKind.late, label: Text('Retard'), icon: Icon(Icons.more_time_rounded)),
                ],
                selected: {kind},
                onSelectionChanged: (v) => setD(() => kind = v.first),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(kind == RequestKind.late ? 'Le' : 'Du'),
                trailing: Text(fmtDate(from)),
                onTap: () async {
                  final d = await pick(ctx, from);
                  if (d != null) {
                    setD(() {
                      from = d;
                      if (to.isBefore(d)) to = d;
                    });
                  }
                },
              ),
              if (kind == RequestKind.absence)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Au'),
                  trailing: Text(fmtDate(to)),
                  onTap: () async {
                    final d = await pick(ctx, to);
                    if (d != null && !d.isBefore(from)) setD(() => to = d);
                  },
                ),
              if (kind == RequestKind.late)
                TextField(
                  controller: hours,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Temps en plus', suffixText: 'h', helperText: 'Ex. 0,5 pour 30 min'),
                ),
              const SizedBox(height: 8),
              TextField(controller: msg, maxLines: 2, decoration: const InputDecoration(labelText: 'Message (facultatif)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Envoyer')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final r = AbsenceRequest(
      id: '${child['childId']}_${DateTime.now().microsecondsSinceEpoch}',
      nannyId: child['nannyId'] as String,
      childId: child['childId'] as String,
      parentEmail: widget.reader.email,
      kind: kind,
      from: from,
      to: kind == RequestKind.late ? from : to,
      extraHours: kind == RequestKind.late ? (parseNum(hours.text) ?? 0) : 0,
      message: msg.text.trim(),
      createdAt: DateTime.now(),
    );
    try {
      await widget.reader.sendRequest(r.toJson());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demande envoyée à votre assistante maternelle.')));
      setState(() => _requests = [r, ..._requests]);
    } catch (e) {
      if (mounted) showError(context, "Envoi impossible : $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Espace parent'),
        actions: [
          IconButton(icon: const Icon(Icons.sync), onPressed: () => setState(() => data = _load())),
          const UpdateGearButton(),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'out') return widget.onSignOut();
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Supprimer mon compte ?'),
                  content: const Text('Votre compte parent sera supprimé. Action irréversible.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
                  ],
                ),
              );
              if (ok != true) return;
              try {
                await widget.onDeleteAccount?.call();
              } catch (e) {
                if (context.mounted) showError(context, 'Reconnectez-vous puis réessayez ($e).');
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'out', child: Text('Déconnexion')),
              if (widget.onDeleteAccount != null) const PopupMenuItem(value: 'del', child: Text('Supprimer mon compte')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newRequest,
        icon: const Icon(Icons.campaign_rounded),
        label: const Text('Prévenir'),
      ),
      body: FutureBuilder(
        future: data,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Center(child: Text('Erreur : ${snap.error}'));
          final (plannings, summaries, _) = snap.data!;
          final requests = _requests;
          if (plannings.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aucun enfant partagé avec cet e-mail. Demandez à votre '
                    'assistante maternelle de vous inviter.', textAlign: TextAlign.center),
              ),
            );
          }
          return ListView(padding: const EdgeInsets.all(8), children: [
            const Disclaimer(compact: true),
            if (requests.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Text('Mes demandes', style: Theme.of(context).textTheme.titleMedium),
              ),
              for (final r in requests.take(5)) _requestTile(r, plannings),
            ],
            for (final p in plannings) ..._child(context, p, summaries.where((s) => s['childId'] == p['childId']).toList()),
            const SizedBox(height: 80),
          ]);
        },
      ),
    );
  }

  List<Widget> _child(BuildContext context, Map<String, dynamic> p, List<Map<String, dynamic>> sums) {
    final color = (p['color'] as num).toInt();
    final sched = WeeklySchedule.fromJson(p['schedule'] == null ? null : Map<String, dynamic>.from(p['schedule']));
    sums.sort((a, b) => ((b['year'] as num) * 100 + (b['month'] as num)).compareTo((a['year'] as num) * 100 + (a['month'] as num)));
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ChildDot(color, size: 20),
              const SizedBox(width: 8),
              Text('${p['firstName']} — planning', style: Theme.of(context).textTheme.titleMedium),
            ]),
            const Divider(),
            for (var d = 1; d <= 7; d++)
              if (sched.slotsFor(d).isNotEmpty)
                Line(weekdayNames[d - 1], sched.slotsFor(d).join(', ')),
            Line('Total hebdomadaire', hrs(sched.weeklyHours), bold: true),
          ]),
        ),
      ),
      for (final s in sums)
        ExpansionTile(
          title: Text('${p['firstName']} — ${monthLabel((s['year'] as num).toInt(), (s['month'] as num).toInt())}'),
          subtitle: Text('Total : ${eur(round2(((s['netSalary'] ?? 0) as num) + ((s['meals'] ?? 0) as num) + ((s['maintenance'] ?? 0) as num)))}'),
          children: [SummaryCard(title: '${p['firstName']}', color: color, s: s)],
        ),
    ];
  }

  Widget _requestTile(AbsenceRequest r, List<Map<String, dynamic>> plannings) {
    final name = plannings.firstWhere((p) => p['childId'] == r.childId, orElse: () => {'firstName': '?'})['firstName'];
    final (label, color, icon) = switch (r.status) {
      RequestStatus.pending => ('En attente', Colors.orange, Icons.hourglass_top_rounded),
      RequestStatus.accepted => ('Acceptée', Colors.green, Icons.check_circle_rounded),
      RequestStatus.refused => ('Refusée', Colors.red, Icons.cancel_rounded),
    };
    final period = r.from == r.to ? fmtDate(r.from) : '${fmtDate(r.from)} → ${fmtDate(r.to)}';
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text('$name · ${r.kind == RequestKind.late ? 'Retard ${hrs(r.extraHours)}' : 'Absence'} · $period'),
      subtitle: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
    );
  }
}
