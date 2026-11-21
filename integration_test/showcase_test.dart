// Démo visuelle : crée un compte et des données d'exemple sur les émulateurs
// puis laisse l'app ouverte pour des captures d'écran.
import 'package:assmatia/main.dart' as app;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'app_test.dart' show tapText, pickDate, pumpUntil, signUp;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('vitrine', (t) async {
    await app.main();
    await t.pumpAndSettle();
    await FirebaseAuth.instance.signOut();
    await t.pump(const Duration(seconds: 6)); // capture : connexion
    await signUp(t, 'vitrine${DateTime.now().millisecondsSinceEpoch}@test.local');
    await tapText(t, 'Je suis assistante maternelle');
    await t.pump(const Duration(seconds: 3));
    if (find.text('Données en mode local').evaluate().isNotEmpty) await tapText(t, 'Plus tard');
    for (final name in ['Lina', 'Tom', 'Jade']) {
      await t.tap(find.byType(FloatingActionButton));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Prénom'), name);
      await t.tap(find.byType(GestureDetector).at(name == 'Tom' ? 2 : name == 'Jade' ? 4 : 0), warnIfMissed: false);
      await tapText(t, 'Enregistrer');
      await tapText(t, name);
      await tapText(t, 'Nouveau contrat');
      await pickDate(t, 'Date de début', '01/09/2026');
      await tapText(t, 'Enregistrer');
      await pumpUntil(t, find.text('Du 01/09/2026'));
      await t.tap(find.byType(BackButton).first);
      await t.pumpAndSettle();
    }
    for (final tab in ['Enfants', 'Planning', 'Suivi', 'Récaps', 'Fiscal']) {
      await tapText(t, tab);
      await t.pump(const Duration(seconds: 7)); // capture
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
