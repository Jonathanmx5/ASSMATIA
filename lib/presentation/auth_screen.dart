import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import 'common.dart';

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

  Future<void> _go() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final a = FirebaseAuth.instance;
      if (signup) {
        await a.createUserWithEmailAndPassword(email: email.text.trim(), password: pwd.text);
      } else {
        await a.signInWithEmailAndPassword(email: email.text.trim(), password: pwd.text);
      }
    } on FirebaseAuthException catch (e) {
      error = e.message ?? e.code;
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 32),
          const Icon(Icons.child_friendly, size: 64),
          Text('ASSMATIA', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
          const Text('Gestion des contrats d\'accueil', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail')),
          TextField(controller: pwd, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe')),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 16),
          FilledButton(onPressed: busy ? null : _go, child: Text(signup ? 'Créer un compte' : 'Se connecter')),
          TextButton(
            onPressed: () => setState(() => signup = !signup),
            child: Text(signup ? 'J\'ai déjà un compte' : 'Créer un compte'),
          ),
          const Disclaimer(),
        ]),
      ),
    );
  }
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
