import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/backend.dart';
import 'data/nanny_store.dart';
import 'presentation/auth_screen.dart';
import 'presentation/nanny/nanny_home.dart';
import 'presentation/parent/parent_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  var firebaseOk = false;
  try {
    // Nécessite android/app/google-services.json (voir README).
    await Firebase.initializeApp();
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
    firebaseOk = true;
  } catch (_) {
    firebaseOk = false;
  }
  runApp(AssmatApp(firebaseOk: firebaseOk));
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

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) return const AuthScreen();
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          key: ValueKey(user.uid),
          future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
          builder: (context, roleSnap) {
            if (!roleSnap.hasData) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final role = roleSnap.data!.data()?['role'];
            void signOut() => FirebaseAuth.instance.signOut();
            if (role == 'parent') {
              return ParentHome(
                reader: ParentReader(FirebaseFirestore.instance, (user.email ?? '').toLowerCase()),
                onSignOut: signOut,
              );
            }
            if (role == 'nanny') {
              return NannyHome(
                store: NannyStore(FirestoreNannyBackend(user.uid, FirebaseFirestore.instance)),
                onSignOut: signOut,
              );
            }
            return RolePicker(user: user);
          },
        );
      },
    );
  }
}
