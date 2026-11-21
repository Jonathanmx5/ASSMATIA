# ASSMATIA

Application Android (Flutter) pour **assistantes maternelles agréées** : contrats et avenants, plannings,
suivi quotidien, salaires, indemnités, déductions d'absence, congés payés et bilan fiscal annuel —
avec partage **en lecture seule** du planning et des récapitulatifs aux parents employeurs.

> ⚠️ Les calculs sont fournis à titre d'aide et de simulation. Seuls les montants officiels
> (Pajemploi, URSSAF, administration fiscale) font foi.

## Fonctionnalités

**Assistante maternelle**
- Fiches enfants (prénom, couleur, archivage) et invitation des parents par e-mail.
- Contrats en **année complète** ou **incomplète**, **avenants datés** (`effectiveFrom`) sans réécriture du passé ;
  contrôle des chevauchements de contrats et de tranches horaires.
- Planning hebdomadaire multi-enfants (jours fériés et congés visibles).
- Suivi du jour : présence, horaires réels, absences déduites ou non, indemnités ;
  « Tous présents » en un geste, absence sur toute la semaine.
- Récapitulatif mensuel : mensualisation brute, déduction **Cour de cassation**, brut du mois, **net estimé**
  (taux réglable), indemnités repas et entretien, détail jour par jour, **validation / verrouillage** du mois.
- **Congés payés** estimés (10 % ou maintien de salaire, le plus favorable).
- **Bilan fiscal** sur l'année civile, tous enfants confondus (abattement 3 × SMIC par jour ≥ 8 h,
  prorata en dessous), SMIC configurable, revenu net imposable plafonné à 0.
- Réglages : périodes de congés / semaines non programmées, export et import JSON, suppression du compte.

**Parent employeur**
- Consultation du planning et des récapitulatifs de **son** enfant uniquement, après vérification de l'e-mail.

**Comptes** : e-mail / mot de passe ou **compte Google**, mot de passe oublié.

## Règles de calcul

| Élément | Formule |
|---|---|
| Mensualisation | taux × heures hebdo × semaines (52 en année complète) / 12 |
| Mois incomplet / avenant en cours de mois | prorata jour par jour des heures prévues |
| Déduction d'absence | salaire mensuel × heures d'absence / heures potentielles du mois (0 si aucune) |
| Entretien | max(forfait journalier, montant horaire × heures du jour) |
| Abattement fiscal | ≥ 8 h : 3 × SMIC ; < 8 h : heures / 8 × 3 × SMIC (jours effectifs uniquement) |
| Revenu net imposable | max(0, revenus imposables − abattement) |

Les jours fériés (métropole) sont payés sans accueil ; les jours futurs sont prévisionnels.
Tous les montants sont arrondis au centime en fin de calcul.

## Architecture

```
lib/
  domain/        modèles + moteur de calcul pur (engine.dart)
  data/          NannyStore, backends Firestore / fichier local, mise à jour de l'app
  presentation/  écrans assistante maternelle, parent, connexion
firestore.rules  sécurité : écriture réservée à l'assmat, lecture parent limitée à son enfant
```

- **Firebase** : Authentication (e-mail, Google) et Cloud Firestore avec cache hors ligne.
  Les écritures ne bloquent pas l'interface ; les erreurs sont affichées.
- Les parents ne lisent que `sharedPlannings` et `monthlySummaries` (e-mail vérifié requis) ;
  contrats, suivis et données fiscales restent privés.

## Développement

Prérequis : Flutter 3.x, Android SDK, Node.js et Firebase CLI.

```bash
flutter pub get
flutter run
```

Configuration Firebase : `android/app/google-services.json` (projet `assmatia-38810`) ;
pour un autre projet, remplacez ce fichier et l'ID client Web Google dans `lib/config.dart`.

### Tests

```bash
flutter test                         # moteur de calcul et couche données
cd rules_test && npm install && npm test   # règles Firestore (émulateur)
```

Tests de bout en bout sur émulateur Android contre les émulateurs Firebase :

```bash
firebase emulators:start --only auth,firestore --project assmatia-38810 --config firebase.emulators.json
flutter test integration_test/app_test.dart -d emulator-5554 --dart-define=USE_EMULATOR=true
```

### Déploiement des règles

```bash
firebase deploy --only firestore:rules
```

## Hors périmètre V1

Paiement / abonnement, export PDF, notifications push, plannings multi-rythmes, majorations
(heures supplémentaires, jours fériés travaillés).
