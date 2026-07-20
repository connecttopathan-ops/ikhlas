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
    // On a cold start Firebase restores the persisted session ASYNCHRONOUSLY,
    // so reading currentUser after a fixed delay can still see null and bounce
    // a signed-in member to /landing. Wait for the first authoritative auth
    // event, overlapped with the splash animation so there's no added delay:
    // for a signed-in user this resolves as soon as the session restores; for
    // a genuinely signed-out user it times out at the animation length and we
    // fall through to /landing — no extra wait either way.
    final authReady = auth.currentUser != null
        ? Future<User?>.value(auth.currentUser)
        : auth
            .authStateChanges()
            .firstWhere((u) => u != null)
            .timeout(const Duration(milliseconds: 2600), onTimeout: () => null);
    final results = await Future.wait<Object?>([
      authReady,
      Future<void>.delayed(const Duration(milliseconds: 2600)),
    ]);
    final user = results[0] as User?;

    // Already signed in → resume where they left off; otherwise the
    // application landing. (No landing/login bounce for returning members.)
    String route = '/landing';
    if (user != null) {
      try {
        route = await ApplicationRepository().resolveEntryRoute();
      } catch (_) {}
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
