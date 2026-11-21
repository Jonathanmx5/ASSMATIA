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
