import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/backend.dart';
import 'data/updater.dart';
import 'data/nanny_store.dart';
import 'presentation/auth_screen.dart';
import 'presentation/nanny/nanny_home.dart';
import 'presentation/parent/parent_home.dart';

/// `--dart-define=USE_EMULATOR=true` : utilise les émulateurs Firebase.
const kUseEmulator = bool.fromEnvironment('USE_EMULATOR');
const kEmulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: '10.0.2.2');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  var firebaseOk = false;
  try {
    // Nécessite android/app/google-services.json (voir README).
    await Firebase.initializeApp();
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: !kUseEmulator);
    if (kUseEmulator) {
      // Tests : émulateurs Firebase locaux (10.0.2.2 = PC hôte vu de l'émulateur Android).
      await FirebaseAuth.instance.useAuthEmulator(kEmulatorHost, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(kEmulatorHost, 8080);
    }
    firebaseOk = true;
  } catch (_) {
    firebaseOk = false;
  }
  runApp(AssmatApp(firebaseOk: firebaseOk));
  if (!kUseEmulator) Updater.instance.check();
}

class AssmatApp extends StatelessWidget {
  final bool firebaseOk;
  const AssmatApp({super.key, required this.firebaseOk});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ASSMATIA',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(colorSchemeSeed: const Color(0xFF7E57C2), useMaterial3: true),
      home: firebaseOk ? const AuthGate() : NannyHome(store: NannyStore(LocalFileBackend())),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  int _refresh = 0;
  NannyStore? _store;

  NannyStore _storeFor(String uid) {
    final cur = _store;
    if (cur != null && (cur.backend as FirestoreNannyBackend).nannyId == uid) return cur;
    return _store = NannyStore(FirestoreNannyBackend(uid, FirebaseFirestore.instance));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) return const AuthScreen();
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          key: ValueKey('${user.uid}-$_refresh'),
          future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
          builder: (context, roleSnap) {
            if (roleSnap.hasError) {
              return Scaffold(body: Center(child: Text('Connexion impossible : ${roleSnap.error}')));
            }
            if (!roleSnap.hasData) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final role = roleSnap.data!.data()?['role'];
            void signOut() => signOutEverywhere();
            Future<void> reset() => FirebaseAuth.instance.sendPasswordResetEmail(email: user.email ?? '');
            if (role == 'parent') {
              final current = FirebaseAuth.instance.currentUser ?? user;
              if (!current.emailVerified) {
                return VerifyEmailScreen(user: current, onVerified: () => setState(() => _refresh++));
              }
              return ParentHome(
                reader: ParentReader(FirebaseFirestore.instance, (user.email ?? '').toLowerCase()),
                onSignOut: signOut,
                onDeleteAccount: deleteCurrentAccount,
              );
            }
            if (role == 'nanny') {
              return NannyHome(
                store: _storeFor(user.uid),
                onSignOut: signOut,
                onDeleteAccount: deleteCurrentAccount,
                onResetPassword: reset,
              );
            }
            return RolePicker(user: user);
          },
        );
      },
    );
  }
}
