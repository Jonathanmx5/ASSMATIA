# ASSMATIA — application Android pour assistantes maternelles (V1)

Flutter/Dart. Calculs fournis à titre d'aide/simulation : seuls les montants officiels font foi.

## Structure
- `lib/domain/` — modèles (enfants, contrats, avenants `effectiveFrom`, plannings, suivis) et `engine.dart` :
  résolution des avenants à une date, mensualisation (`heures hebdo × semaines / 12 × taux`),
  indemnités repas (par jour) et entretien (`max(forfait jour, €/h × heures)`), déduction Cour de cassation
  (`salaire × heures d'absence / heures potentielles du mois`, 0 si 0), abattement fiscal annuel multi-enfants
  (≥ 8 h : 3 × SMIC ; < 8 h : h/8 × 3 × SMIC), revenu net imposable plafonné à 0, arrondi final au centime.
  Entrée/sortie ou avenant en cours de mois : salaire proratisé jour par jour selon les heures prévues.
- `lib/data/` — `NannyStore` (cache mémoire, synchronisation à l'ouverture), backends Firestore (cache hors ligne
  activé) et fichier local (repli automatique si Firebase n'est pas configuré → « Mode local », sans partage).
  À chaque modification, l'app publie `sharedPlannings/{childId}` et `monthlySummaries/{childId_AAAA-MM}`
  (13 derniers mois) — seules données lisibles par les parents.
- `lib/presentation/` — assmat : Enfants (fiches, contrats, avenants, partage), Planning semaine multi-enfants,
  Suivi du jour, Récaps mensuels, Bilan fiscal (SMIC configurable, revenus saisissables). Parent : planning +
  récaps en lecture seule.
- `firestore.rules` — écriture réservée à `nannyId == uid` (rôle `nanny`) ; parents : lecture des seules vues
  partagées dont `parentEmails` contient leur e-mail ; aucun accès aux contrats, suivis ni au fiscal.
- `test/engine_test.dart` — 18 tests unitaires du moteur.

## Activer Firebase (synchronisation + partage parents)
1. Créer un projet Firebase, ajouter l'app Android `fr.assmatia.assmatia`, activer Auth « E-mail/mot de passe » et Firestore.
2. Déposer `google-services.json` dans `android/app/` et ajouter le plugin `com.google.gms.google-services`
   (`android/settings.gradle.kts` + `android/app/build.gradle.kts`) — ou lancer `flutterfire configure`.
3. Déployer les règles : `firebase deploy --only firestore:rules`.
4. Inviter un parent depuis la fiche enfant (e-mail) ; il crée un compte avec cet e-mail et choisit « Parent ».

## Commandes
`flutter test` · `flutter analyze` · `flutter build apk`

Hors V1 : paiement, PDF, notifications, multi-rythmes, majorations.

## Évolutions (lot 2)
- Sécurité : accès parent conditionné à un e-mail **vérifié** ; révocation d'un parent appliquée à tout l'historique ;
  tests des règles : `cd rules_test && npm test` (émulateur Firestore, 9 cas).
- Hors ligne : écritures non bloquantes (cache Firestore), erreurs affichées ; publications groupées en lots.
- Calculs : brut / net estimé (taux réglable), jours fériés automatiques, périodes de congés / semaines non
  programmées, jours futurs en prévisionnel, abattement limité aux jours effectifs, estimation des congés payés
  (10 % vs maintien, récap de mai/juin), contrôle des chevauchements (contrats, tranches).
- Écrans : « Tous présents », absence sur la semaine, détail jour par jour, formule Cour de cassation,
  validation/verrouillage d'un mois, réglages (congés, taux net, export/import JSON), migration mode local → cloud,
  mot de passe oublié, suppression de compte, partage du message d'invitation.
