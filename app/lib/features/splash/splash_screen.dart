import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
import '../../data/repositories/application_repository.dart';

/// Splash — the brand logo lockup (14b light) rises and fades in, then the
/// tagline. Centered rite composition on the sage ground.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _stagger =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    // Status-bar style is set correctly (dark icons on the light ground)
    // once in main.dart — don't override it here.
    _stagger.forward();
    _handoff();
  }

  /// Resolves the restored session on a cold start. With Firebase Auth 6+
  /// (Android 16-compatible) the persisted user is usually present in
  /// `currentUser` on the first frame; when it isn't yet, we wait briefly for
  /// the first authStateChanges emission. A genuinely signed-out user emits
  /// null and no user follows, so the wait tops out at the ceiling — kept
  /// short so signed-out users don't sit on the splash.
  Future<User?> _restoredUser(FirebaseAuth auth) async {
    if (auth.currentUser != null) return auth.currentUser;
    final done = Completer<User?>();
    late final StreamSubscription<User?> sub;
    sub = auth.authStateChanges().listen((u) {
      if (u != null && !done.isCompleted) done.complete(u);
    });
    final user = await done.future.timeout(const Duration(seconds: 5),
        onTimeout: () => auth.currentUser);
    await sub.cancel();
    return user;
  }

  Future<void> _handoff() async {
    final auth = FirebaseAuth.instance;
    final results = await Future.wait<Object?>([
      _restoredUser(auth),
      // Floor, not deadline: keeps the brand rite on screen even when auth
      // resolves instantly. Auth slower than this just extends the splash.
      Future<void>.delayed(const Duration(milliseconds: 2600)),
    ]);
    final user = (results[0] as User?) ?? auth.currentUser;

    // Signed in → resume where they left off. If the entry-route lookup fails
    // (offline blip), retry once, then fall back to an IN-APP surface — never
    // /landing, which reads as "signed out". The router guards re-route once
    // the user doc stream heals.
    String route = '/landing';
    if (user != null) {
      try {
        route = await ApplicationRepository().resolveEntryRoute();
      } catch (_) {
        try {
          await Future<void>.delayed(const Duration(seconds: 1));
          route = await ApplicationRepository().resolveEntryRoute();
        } catch (_) {
          route = '/home';
        }
      }
    }
    if (mounted) context.go(route);
  }

  @override
  void dispose() {
    _stagger.dispose();
    super.dispose();
  }

  Widget _rise(double from, double to, Widget child) {
    final anim = CurvedAnimation(
        parent: _stagger, curve: Interval(from, to, curve: Curves.easeOutCubic));
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
            offset: Offset(0, 14 * (1 - anim.value)), child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IkhlasScaffold(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _rise(0.0, 0.7, const IkhlasLogo(size: 56)),
            const SizedBox(height: 22),
            _rise(0.4, 1.0,
                Text('Where nikah begins with deen',
                    style: AppType.fraunces(15,
                        color: DarkTokens.muted(.7), style: FontStyle.italic))),
          ],
        ),
      ),
    );
  }
}
