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

  Future<void> _handoff() async {
    final auth = FirebaseAuth.instance;
    final t0 = DateTime.now();
    // On a cold start Firebase restores the persisted session ASYNCHRONOUSLY.
    // Wait for the FIRST authStateChanges event — that emission IS the
    // authoritative restored state (a signed-out user gets null immediately;
    // a signed-in user gets their session as soon as it restores). The old
    // code waited for a NON-null event with a 2.6s timeout, which mislabelled
    // any slower-than-2.6s restore as "signed out" and bounced a signed-in
    // member to /landing — the repeated-logout bug. No arbitrary deadline
    // now; the 10s ceiling is only a pathological-hang escape hatch.
    final authReady = auth.currentUser != null
        ? Future<User?>.value(auth.currentUser)
        : auth
            .authStateChanges()
            .first
            .timeout(const Duration(seconds: 10), onTimeout: () => null);
    final results = await Future.wait<Object?>([
      authReady,
      // Floor, not deadline: keeps the brand rite on screen even when auth
      // resolves instantly. Auth slower than this just extends the splash.
      Future<void>.delayed(const Duration(milliseconds: 2600)),
    ]);
    final user = results[0] as User?;
    debugPrint('[auth-guard] splash: restored=${user != null} '
        'in ${DateTime.now().difference(t0).inMilliseconds}ms');

    // Signed in → resume where they left off. If the entry-route lookup fails
    // (offline blip), fall back to an IN-APP surface — never /landing, which
    // reads as "signed out". The router guards re-route once the user doc
    // stream heals.
    String route = '/landing';
    if (user != null) {
      try {
        route = await ApplicationRepository().resolveEntryRoute();
      } catch (e) {
        debugPrint('[auth-guard] splash: resolveEntryRoute failed ($e) — '
            'retrying once');
        try {
          await Future<void>.delayed(const Duration(seconds: 1));
          route = await ApplicationRepository().resolveEntryRoute();
        } catch (e2) {
          debugPrint('[auth-guard] splash: retry failed ($e2) — '
              'falling back to /home');
          route = '/home';
        }
      }
    }
    debugPrint('[auth-guard] splash: handoff -> $route');
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
