import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';

import '../main.dart';
import 'common.dart';
import 'update_widgets.dart';
import 'theme.dart';
import 'package:flutter_animate/flutter_animate.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final pwd = TextEditingController();
  bool signup = false;
  String? error;
  bool busy = false;

  /// Connexion Google : l'e-mail Google est déjà vérifié, ce qui satisfait
  /// directement la règle d'accès des parents.
  Future<void> _google() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await signInWithGoogle();
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) error = 'Connexion Google impossible : ${e.description ?? e.code.name}';
    } on FirebaseAuthException catch (e) {
      error = e.message ?? e.code;
    } catch (e) {
      error = 'Connexion Google impossible : $e';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _go() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final a = FirebaseAuth.instance;
      if (signup) {
        final cred = await a.createUserWithEmailAndPassword(email: email.text.trim(), password: pwd.text);
        await cred.user?.sendEmailVerification();
      } else {
        await a.signInWithEmailAndPassword(email: email.text.trim(), password: pwd.text);
      }
    } on FirebaseAuthException catch (e) {
      error = e.message ?? e.code;
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _forgot() async {
    final e = email.text.trim();
    if (!e.contains('@')) {
      setState(() => error = 'Saisissez votre e-mail ci-dessus.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: e);
      setState(() => error = 'Si un compte existe, un e-mail de réinitialisation a été envoyé.');
    } on FirebaseAuthException catch (x) {
      setState(() => error = x.message ?? x.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: Kid.skyGradient),
        child: BubbleBackground(
          child: SafeArea(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
              const Align(alignment: Alignment.centerRight, child: UpdateGearButton()),
              const Center(child: KidLogo(size: 120)).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
              const SizedBox(height: 12),
              Text('ASSMATIA', textAlign: TextAlign.center, style: tt.headlineLarge?.copyWith(color: Colors.white, letterSpacing: 1.5))
                  .animate().fadeIn(delay: 150.ms).slideY(begin: .3),
              Text("Le carnet de bord des petits et de leur nounou",
                      textAlign: TextAlign.center,
                      style: tt.titleMedium?.copyWith(color: Colors.white.withValues(alpha: .95)))
                  .animate().fadeIn(delay: 300.ms),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [BoxShadow(color: Kid.lavender.withValues(alpha: .3), blurRadius: 30, offset: const Offset(0, 12))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(signup ? 'Créer mon compte' : 'Bon retour parmi nous !',
                      style: tt.titleLarge, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Kid.coral),
                    onPressed: busy ? null : _google,
                    icon: const Icon(Icons.account_circle_rounded),
                    label: const Text('Continuer avec Google'),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Row(children: [
                      Expanded(child: Divider()),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('ou par e-mail')),
                      Expanded(child: Divider()),
                    ]),
                  ),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_rounded)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: pwd,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Mot de passe', prefixIcon: Icon(Icons.lock_rounded)),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(error!, style: const TextStyle(color: Kid.coral, fontWeight: FontWeight.w700)),
                    ).animate().shake(hz: 3, offset: const Offset(4, 0)),
                  const SizedBox(height: 16),
                  OutlinedButton(onPressed: busy ? null : _go, child: Text(signup ? 'Créer un compte' : 'Se connecter')),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    TextButton(
                      onPressed: () => setState(() => signup = !signup),
                      child: Text(signup ? "J'ai déjà un compte" : 'Créer un compte'),
                    ),
                    if (!signup) TextButton(onPressed: _forgot, child: const Text('Mot de passe oublié')),
                  ]),
                ]),
              ).animate().fadeIn(delay: 400.ms, duration: 500.ms).slideY(begin: .15, curve: Curves.easeOutCubic),
              const SizedBox(height: 12),
              const Disclaimer(compact: true),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Écran bloquant tant que l'e-mail n'est pas vérifié (requis pour les
/// parents : les règles d'accès exigent un e-mail vérifié).
class VerifyEmailScreen extends StatefulWidget {
  final User user;
  final VoidCallback onVerified;
  const VerifyEmailScreen({super.key, required this.user, required this.onVerified});
  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  String? msg;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Vérifiez votre e-mail'), actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut()),
        ]),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Text('Un lien de confirmation a été envoyé à ${widget.user.email}. '
              'Ouvrez-le, puis revenez ici. Cette vérification protège les données de votre enfant.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              await widget.user.reload();
              final u = FirebaseAuth.instance.currentUser;
              if (u?.emailVerified ?? false) {
                await u!.getIdToken(true); // jeton à jour pour les règles
                widget.onVerified();
              } else {
                setState(() => msg = "L'e-mail n'est pas encore vérifié.");
              }
            },
            child: const Text("J'ai cliqué sur le lien"),
          ),
          TextButton(
            onPressed: () async {
              await widget.user.sendEmailVerification();
              setState(() => msg = 'E-mail renvoyé.');
            },
            child: const Text("Renvoyer l'e-mail"),
          ),
          if (msg != null) Text(msg!),
        ]),
      );
}

/// Supprime le profil et le compte Firebase de l'utilisateur courant.
Future<void> deleteCurrentAccount() async {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) return;
  await FirebaseFirestore.instance.collection('users').doc(u.uid).delete();
  await u.delete();
}

/// Choix du rôle à la première connexion (définitif).
class RolePicker extends StatelessWidget {
  final User user;
  const RolePicker({super.key, required this.user});

  Future<void> _set(BuildContext context, String role) async {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'role': role,
      'email': (user.email ?? '').toLowerCase(),
    });
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()), (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Votre profil'), actions: [
        IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut()),
      ]),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Text('Ce choix est définitif pour ce compte.'),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.child_care),
            title: const Text('Je suis assistante maternelle'),
            subtitle: const Text('Gestion complète des enfants, contrats, suivis et calculs'),
            onTap: () => _set(context, 'nanny'),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.family_restroom),
            title: const Text('Je suis parent employeur'),
            subtitle: const Text('Consultation du planning et des récapitulatifs de mon enfant'),
            onTap: () => _set(context, 'parent'),
          ),
        ),
      ]),
    );
  }
}

bool _googleReady = false;

Future<void> signInWithGoogle() async {
  final g = GoogleSignIn.instance;
  if (!_googleReady) {
    await g.initialize(serverClientId: kGoogleServerClientId.isEmpty ? null : kGoogleServerClientId);
    _googleReady = true;
  }
  final account = await g.authenticate();
  final idToken = account.authentication.idToken;
  if (idToken == null) throw StateError('jeton Google absent');
  await FirebaseAuth.instance.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
}

/// Déconnexion complète (Firebase + choix du compte Google).
Future<void> signOutEverywhere() async {
  await FirebaseAuth.instance.signOut();
  try {
    await GoogleSignIn.instance.signOut();
  } catch (_) {}
}
