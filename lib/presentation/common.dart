import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/models.dart';

final euro = NumberFormat.currency(locale: 'fr_FR', symbol: '€', decimalDigits: 2);
final hoursFmt = NumberFormat('0.##', 'fr_FR');
String eur(num v) => euro.format(v);
String hrs(num v) => '${hoursFmt.format(v)} h';

const weekdayNames = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
const weekdayShort = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
const monthNames = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
  'août', 'septembre', 'octobre', 'novembre', 'décembre'];

String fmtDate(DateTime d) => DateFormat('dd/MM/yyyy').format(d);
String monthLabel(int y, int m) => '${monthNames[m - 1]} $y';

const kChildColors = <int>[
  0xFFE57373, 0xFF64B5F6, 0xFF81C784, 0xFFFFB74D, 0xFFBA68C8,
  0xFF4DB6AC, 0xFFF06292, 0xFFA1887F, 0xFF90A4AE, 0xFFDCE775,
];

/// Avertissement légal affiché dans l'application.
class Disclaimer extends StatelessWidget {
  final bool compact;
  const Disclaimer({super.key, this.compact = false});
  static const text =
      'Calculs fournis à titre d\'aide et de simulation. Seuls les montants '
      'officiels (Pajemploi, URSSAF, administration fiscale) font foi.';
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.all(8),
        padding: EdgeInsets.all(compact ? 8 : 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ]),
      );
}

class ChildDot extends StatelessWidget {
  final int color;
  final double size;
  const ChildDot(this.color, {super.key, this.size = 14});
  @override
  Widget build(BuildContext context) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Color(color), shape: BoxShape.circle));
}

class Line extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const Line(this.label, this.value, {super.key, this.bold = false});
  @override
  Widget build(BuildContext context) {
    final st = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(label, style: st)),
        Text(value, style: st),
      ]),
    );
  }
}

/// Affichage d'un récapitulatif mensuel (partagé assmat / parent).
class SummaryCard extends StatelessWidget {
  final String title;
  final int color;
  final Map<String, dynamic> s; // MonthlySummary.toJson()
  const SummaryCard({super.key, required this.title, required this.color, required this.s});
  double _d(String k) => ((s[k] ?? 0) as num).toDouble();
  @override
  Widget build(BuildContext context) {
    final net = _d('netSalary'), meals = _d('meals'), maint = _d('maintenance');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ChildDot(color),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          ]),
          const Divider(),
          Line('Heures prévues', hrs(_d('plannedHours'))),
          Line('Heures effectuées', hrs(_d('workedHours'))),
          Line('Jours d\'accueil', '${s['daysPresent'] ?? 0}'),
          Line('Taux horaire', eur(_d('hourlyRate'))),
          const Divider(),
          Line('Salaire mensualisé', eur(_d('baseSalary'))),
          Line('Déduction absences (${hrs(_d('absenceHours'))})',
              '- ${eur(_d('absenceDeduction'))}'),
          Line('Salaire net du mois', eur(net), bold: true),
          Line('Indemnités de repas', eur(meals)),
          Line('Indemnités d\'entretien', eur(maint)),
          const Divider(),
          Line('Total à verser', eur(round2(net + meals + maint)), bold: true),
        ]),
      ),
    );
  }
}

Future<int?> pickTime(BuildContext context, int minutes) async {
  final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60));
  return t == null ? null : t.hour * 60 + t.minute;
}

double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
