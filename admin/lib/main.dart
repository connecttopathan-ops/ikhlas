import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'review_queue.dart';
import 'tokens.dart';

/// Ikhlas admin — internal review dashboard (Flutter Web).
/// Moderator-gated by Firebase custom claim `moderator: true`;
/// firestore.rules/storage.rules enforce the same claim server-side,
/// so this UI gate is convenience, not security.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Surface build-time exceptions inline instead of Flutter web's default
  // featureless grey box, and — because each card/panel is its own widget —
  // confine the failure to that widget so one malformed document can't blank
  // out an entire tab.
  ErrorWidget.builder = (FlutterErrorDetails details) => Container(
        color: T.bg,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        child: Text(
          'Could not render this item.\n${details.exceptionAsString()}',
          textAlign: TextAlign.center,
          style: T.inter(12.5, color: T.muted, height: 1.5),
        ),
      );
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ikhlaas — Review',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: T.bg,
        colorScheme: const ColorScheme.dark(
            surface: T.bg, primary: T.gold, onPrimary: T.ctaText),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme)
            .apply(bodyColor: T.ivory, displayColor: T.ivory),
      ),
      home: const AuthGate(),
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
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Centered(child: CircularProgressIndicator());
        }
        if (user == null) return const _SignInScreen();
        return FutureBuilder<IdTokenResult>(
          future: user.getIdTokenResult(),
          builder: (context, tokenSnap) {
            if (!tokenSnap.hasData) {
              return const _Centered(child: CircularProgressIndicator());
            }
            final isModerator = tokenSnap.data!.claims?['moderator'] == true;
            if (!isModerator) return _NotAuthorized(email: user.email ?? '');
            return const ReviewQueueScreen();
          },
        );
      },
    );
  }
}

class _SignInScreen extends StatelessWidget {
  const _SignInScreen();

  @override
  Widget build(BuildContext context) {
    return _Centered(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Ikhlaas', style: T.fraunces(34, color: T.gold)),
        const SizedBox(height: 6),
        Text('Application review', style: T.inter(14, color: T.muted)),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () =>
              FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider()),
          style: FilledButton.styleFrom(
              backgroundColor: T.gold,
              foregroundColor: T.ctaText,
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 18)),
          child: Text('Sign in with Google',
              style: T.inter(15, weight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _NotAuthorized extends StatelessWidget {
  final String email;
  const _NotAuthorized({required this.email});

  @override
  Widget build(BuildContext context) {
    return _Centered(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Not authorized', style: T.fraunces(26, color: T.ivory)),
        const SizedBox(height: 10),
        Text('$email does not have the moderator role.',
            style: T.inter(14, color: T.muted)),
        const SizedBox(height: 20),
        TextButton(
          onPressed: () => FirebaseAuth.instance.signOut(),
          child: Text('Sign out', style: T.inter(14, color: T.gold)),
        ),
      ]),
    );
  }
}

class _Centered extends StatelessWidget {
  final Widget child;
  const _Centered({required this.child});
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: child));
}
