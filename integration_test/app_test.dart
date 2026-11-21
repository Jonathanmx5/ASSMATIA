// Test de bout en bout sur appareil Android, contre les émulateurs Firebase.
// Lancer : voir README (section « Tests de bout en bout »).
import 'dart:convert';
import 'dart:io';

import 'package:assmatia/main.dart' as app;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const project = 'assmatia-38810';
final stamp = DateTime.now().millisecondsSinceEpoch;
final nannyEmail = 'assmat$stamp@test.local';
final parentEmail = 'parent$stamp@test.local';
const pwd = 'motdepasse-test';

/// Montant affiché (insensible aux espaces insécables du format français).
Finder money(String s) => find.byWidgetPredicate((w) =>
    w is Text && (w.data ?? '').replaceAll(' ', ' ').replaceAll(' ', ' ') == s);

Future<void> pumpUntil(WidgetTester t, Finder f, {int seconds = 20}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Introuvable après ${seconds}s : $f');
}

/// Attend [f] puis, s'il reste hors écran dans une liste paresseuse, fait défiler.
Future<void> reveal(WidgetTester t, Finder f) async {
  try {
    await pumpUntil(t, f, seconds: 4);
  } on TestFailure {
    final lists = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    if (lists.evaluate().isEmpty) rethrow;
    await t.scrollUntilVisible(f, 300, scrollable: lists.first, maxScrolls: 30);
  }
}

Future<void> tapText(WidgetTester t, String s) async {
  final f = find.text(s);
  await reveal(t, f);
  await t.ensureVisible(f.first);
  await t.pumpAndSettle();
  await t.tap(f.first);
  await t.pumpAndSettle();
}

Future<void> tapIcon(WidgetTester t, IconData i) async {
  final f = find.byIcon(i);
  await pumpUntil(t, f);
  await t.tap(f.first);
  await t.pumpAndSettle();
}

Future<void> fill(WidgetTester t, String label, String v) async {
  final f = find.widgetWithText(TextField, label);
  await reveal(t, f);
  await t.ensureVisible(f.first);
  await t.enterText(f.first, v);
  await t.pumpAndSettle();
}

/// Ouvre le sélecteur de date de [tile] et saisit [ddmmyyyy] au clavier.
Future<void> pickDate(WidgetTester t, String tile, String ddmmyyyy) async {
  await tapText(t, tile);
  await tapIcon(t, Icons.edit_outlined);
  await t.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)), ddmmyyyy);
  await t.pumpAndSettle();
  await tapText(t, 'OK');
}

Future<void> signUp(WidgetTester t, String email) async {
  await tapText(t, 'Créer un compte');
  await fill(t, 'E-mail', email);
  await fill(t, 'Mot de passe', pwd);
  await t.tap(find.widgetWithText(OutlinedButton, 'Créer un compte'));
  await t.pumpAndSettle();
}

/// Marque l'e-mail vérifié via l'API de l'émulateur Auth.
Future<void> verifyEmailOnEmulator(String uid) async {
  final c = HttpClient();
  final r = await c.postUrl(Uri.parse(
      'http://${app.kEmulatorHost}:9099/identitytoolkit.googleapis.com/v1/projects/$project/accounts:update'));
  r.headers.set('Authorization', 'Bearer owner');
  r.headers.contentType = ContentType.json;
  r.write(jsonEncode({'localId': uid, 'emailVerified': true}));
  final res = await r.close();
  if (res.statusCode != 200) throw TestFailure('verif e-mail : ${res.statusCode}');
  c.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('parcours complet assistante maternelle puis parent', (t) async {
    await app.main();
    await t.pumpAndSettle();
    await FirebaseAuth.instance.signOut();
    await t.pumpAndSettle();

    // ---------- Assistante maternelle ----------
    await signUp(t, nannyEmail);
    await tapText(t, 'Je suis assistante maternelle');
    await pumpUntil(t, find.text('Aucun enfant. Ajoutez une fiche avec le bouton +.'));
    // Données d'un ancien usage en mode local : proposition de transfert.
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    if (find.text('Données en mode local').evaluate().isNotEmpty) await tapText(t, 'Plus tard');

    for (final name in ['Lina', 'Tom']) {
      await t.tap(find.byType(FloatingActionButton));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Prénom'), name);
      await tapText(t, 'Enregistrer');
    }
    expect(find.text('Lina'), findsOneWidget);
    expect(find.text('Tom'), findsOneWidget);

    // Contrat de Lina au 01/09/2026 : 45 h × 4 € = 780 €/mois.
    await tapText(t, 'Lina');
    await tapText(t, 'Nouveau contrat');
    await pickDate(t, 'Date de début', '01/09/2026');
    expect(money('780,00 €'), findsOneWidget);
    await tapText(t, 'Enregistrer');
    await pumpUntil(t, find.text('Du 01/09/2026'));

    // Contrat qui chevauche : refusé.
    await tapText(t, 'Nouveau contrat');
    await pickDate(t, 'Date de début', '01/10/2026');
    await tapText(t, 'Enregistrer');
    await pumpUntil(t, find.textContaining('chevauche'));
    await t.tap(find.byType(BackButton).first);
    await t.pumpAndSettle();

    // Avenant au 01/11/2026 : taux 5 €.
    await tapText(t, 'Ajouter un avenant');
    await pickDate(t, "Date d'effet", '01/11/2026');
    await fill(t, "Objet de l'avenant", 'Augmentation');
    await fill(t, 'Taux horaire brut', '5');
    await tapText(t, "Enregistrer l'avenant");
    await pumpUntil(t, find.textContaining('À partir du 01/11/2026'));

    // Invitation du parent.
    await tapText(t, 'Inviter un parent');
    await t.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), parentEmail.toUpperCase());
    await tapText(t, 'Autoriser');
    await tapText(t, 'Plus tard');
    expect(find.text(parentEmail), findsOneWidget); // normalisé en minuscules
    await t.tap(find.byType(BackButton).first);
    await t.pumpAndSettle();

    // Planning : semaine du 16/11/2026, férié du 11 visible la semaine précédente.
    await tapText(t, 'Planning');
    expect(find.textContaining('Lina'), findsWidgets);

    // Suivi : vendredi 20/11 absent déduit.
    await tapText(t, 'Suivi');
    final now = DateTime.now();
    final target = DateTime(2026, 11, 20);
    var diff = DateTime(now.year, now.month, now.day).difference(target).inDays;
    while (diff > 0) {
      await t.tap(find.byIcon(Icons.chevron_left));
      await t.pumpAndSettle();
      diff--;
    }
    while (diff < 0) {
      await t.tap(find.byIcon(Icons.chevron_right));
      await t.pumpAndSettle();
      diff++;
    }
    await pumpUntil(t, find.text('Vendredi 20/11/2026'));
    await tapText(t, 'Lina — Selon planning');
    await tapText(t, 'Absent (déduit)');
    await tapText(t, 'Enregistrer');
    await pumpUntil(t, find.textContaining('Absence déduite 9 h'));

    // Récap novembre : 975 € mensualisés, déduction 975 × 9 / 189 = 46,43 €.
    await tapText(t, 'Récaps');
    await pumpUntil(t, find.text('novembre 2026'));
    expect(money('975,00 €'), findsOneWidget);
    expect(money('- 46,43 €'), findsOneWidget);
    expect(money('928,57 €'), findsOneWidget); // brut du mois
    expect(find.textContaining('9 h / 189 h potentielles'), findsOneWidget);

    // Octobre : validé puis figé.
    await t.tap(find.byIcon(Icons.chevron_left).first);
    await t.pumpAndSettle();
    await pumpUntil(t, find.text('octobre 2026'));
    expect(money('780,00 €'), findsWidgets);
    await tapText(t, 'Valider le mois');
    await t.tap(find.widgetWithText(FilledButton, 'Valider'));
    await t.pumpAndSettle();
    await pumpUntil(t, find.text('Validé'));

    // Fiscal : abattement calculé, année partielle.
    await tapText(t, 'Fiscal');
    await pumpUntil(t, find.text('Abattement total'));
    expect(find.textContaining('Année en cours'), findsOneWidget);

    // Réglages : période de congés pour Tom.
    await tapIcon(t, Icons.settings);
    await tapText(t, 'Ajouter une période');
    await tapText(t, 'Enregistrer');
    await pumpUntil(t, find.byIcon(Icons.beach_access));
    await t.tap(find.byType(BackButton).first);
    await t.pumpAndSettle();

    // Laisse le temps aux écritures Firestore d'arriver.
    await t.pump(const Duration(seconds: 3));
    await tapIcon(t, Icons.logout);

    // ---------- Parent ----------
    await signUp(t, parentEmail);
    await tapText(t, 'Je suis parent employeur');
    await pumpUntil(t, find.text("J'ai cliqué sur le lien"));
    await tapText(t, "J'ai cliqué sur le lien");
    expect(find.text("L'e-mail n'est pas encore vérifié."), findsOneWidget);

    await verifyEmailOnEmulator(FirebaseAuth.instance.currentUser!.uid);
    await tapText(t, "J'ai cliqué sur le lien");
    await pumpUntil(t, find.text('Lina — planning'));
    expect(find.textContaining('Tom'), findsNothing); // autre enfant invisible
    expect(find.textContaining('octobre 2026'), findsOneWidget);

    // Lecture seule : les données privées sont refusées.
    for (final c in ['contracts', 'children', 'dailyLogs', 'taxScales']) {
      await expectLater(FirebaseFirestore.instance.collection(c).limit(1).get(), throwsA(isA<FirebaseException>()),
          reason: 'lecture $c');
    }
    await expectLater(
        FirebaseFirestore.instance.collection('monthlySummaries').doc('pirate').set({'x': 1}),
        throwsA(isA<FirebaseException>()));
  });

  testWidgets('révocation du parent et suppression des comptes', (t) async {
    Future<void> signIn(String email) async {
      await fill(t, 'E-mail', email);
      await fill(t, 'Mot de passe', pwd);
      await t.tap(find.widgetWithText(OutlinedButton, 'Se connecter'));
      await t.pumpAndSettle();
    }

    await app.main();
    await t.pumpAndSettle();
    if (FirebaseAuth.instance.currentUser != null) {
      await FirebaseAuth.instance.signOut();
      await t.pumpAndSettle();
    }

    // L'assistante retire l'accès du parent.
    await signIn(nannyEmail);
    await tapText(t, 'Lina');
    await pumpUntil(t, find.text(parentEmail));
    await t.tap(find.byIcon(Icons.remove_circle_outline));
    await t.pumpAndSettle();
    expect(find.text(parentEmail), findsNothing);
    await t.pump(const Duration(seconds: 3));
    await t.tap(find.byType(BackButton).first);
    await t.pumpAndSettle();
    await tapIcon(t, Icons.logout);

    // Le parent ne voit plus rien, y compris l'historique.
    await signIn(parentEmail);
    await pumpUntil(t, find.textContaining('Aucun enfant partagé'));
    final left = await FirebaseFirestore.instance
        .collection('monthlySummaries')
        .where('parentEmails', arrayContains: parentEmail)
        .get();
    expect(left.docs, isEmpty);

    // Suppression du compte parent.
    await tapIcon(t, Icons.more_vert);
    await tapText(t, 'Supprimer mon compte');
    await tapText(t, 'Supprimer');
    await pumpUntil(t, find.text('Continuer avec Google'));

    // Suppression du compte assistante maternelle et de toutes ses données.
    await signIn(nannyEmail);
    await pumpUntil(t, find.text('Lina'));
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await tapIcon(t, Icons.settings);
    await tapText(t, 'Supprimer mon compte et mes données');
    await t.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await t.pumpAndSettle();
    await pumpUntil(t, find.text('Continuer avec Google'));
    expect(FirebaseAuth.instance.currentUser, isNull);
    // Vérification côté serveur (émulateur, règles contournées).
    final c = HttpClient();
    final r = await c.getUrl(Uri.parse(
        'http://${app.kEmulatorHost}:8080/v1/projects/$project/databases/(default)/documents/contracts'));
    r.headers.set('Authorization', 'Bearer owner');
    final body = await (await r.close()).transform(utf8.decoder).join();
    expect(body.contains(uid), isFalse, reason: 'contrats restants');
    c.close();
  });
}
