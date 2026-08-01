import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/build_info.dart';
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

  /// Resolves the RESTORED session, defending against both cold-start races:
  ///  1. `currentUser` is null for a beat while the native SDK restores the
  ///     persisted session (the original repeated-logout bug), and
  ///  2. the firebase_auth plugin can emit a spurious `null` as the FIRST
  ///     authStateChanges event with the real user arriving a moment later —
  ///     so a null first event is NOT trusted as signed-out; it gets a grace
  ///     window for the real restore to land before we conclude logged out.
  /// A genuinely signed-out user emits null and then nothing, so the only
  /// cost of the grace window is ~3s of extra splash for signed-out users.
  // Cold-start diagnostics (TEMPORARY, closed testing): posted to clientDiag.
  bool _diagUserAtInit = false;
  bool _diagNullFirst = false;
  bool _diagTimedOut = false;
  int _diagEvents = 0;
  int _diagRestoreMs = -1; // ms until the persisted user first arrived (-1 = never)

  /// Waits for the restored session. Cold-start data showed authStateChanges
  /// emits null first and the real user (if any) can arrive later than the old
  /// 3s grace allowed — which read as "logged out". Now we wait up to 9s for a
  /// non-null user and record exactly when it lands, so we can tell a SLOW
  /// restore (fixable by waiting) from a session that is genuinely not
  /// persisted (needs a native fix). A truly signed-out user just costs the
  /// full window of splash — acceptable for this diagnostic build.
  Future<User?> _restoredUser(FirebaseAuth auth) async {
    if (auth.currentUser != null) {
      _diagUserAtInit = true;
      _diagRestoreMs = 0;
      return auth.currentUser;
    }
    final sw = Stopwatch()..start();
    final done = Completer<User?>();
    late final StreamSubscription<User?> sub;
    sub = auth.authStateChanges().listen((u) {
      _diagEvents++;
      if (u == null) {
        if (_diagEvents == 1) _diagNullFirst = true;
        return;
      }
      _diagRestoreMs = sw.elapsedMilliseconds;
      if (!done.isCompleted) done.complete(u);
    });
    final user = await done.future.timeout(const Duration(seconds: 9),
        onTimeout: () {
      _diagTimedOut = true;
      return auth.currentUser; // last-chance sync read
    });
    await sub.cancel();
    return user;
  }

  /// Fire-and-forget POST to the clientDiag function (TEMPORARY — removed
  /// when the logout bug is closed). Never blocks or throws into the flow.
  static void _postDiag(Map<String, Object?> data) {
    Future(() async {
      try {
        final c = HttpClient();
        final r = await c.postUrl(Uri.parse(
            'https://asia-south1-ikhlas-caecf.cloudfunctions.net/clientDiag'));
        r.headers.contentType = ContentType.json;
        r.write(jsonEncode(data));
        await (await r.close()).drain<void>();
        c.close();
      } catch (_) {}
    });
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
    final results = await Future.wait<Object?>([
      _restoredUser(auth),
      // Floor, not deadline: keeps the brand rite on screen even when auth
      // resolves instantly. Auth slower than this just extends the splash.
      Future<void>.delayed(const Duration(milliseconds: 2600)),
    ]);
    // Last-chance synchronous re-check: the session may have restored during
    // the animation floor even if the stream race concluded null.
    final user = (results[0] as User?) ?? auth.currentUser;
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
    _postDiag({
      'tag': 'coldstart',
      'build': kBuildTag,
      'userAtInit': _diagUserAtInit,
      'nullFirstEvent': _diagNullFirst,
      'streamTimedOut': _diagTimedOut,
      'events': _diagEvents,
      'restoreMs': _diagRestoreMs,
      'restored': user != null,
      'uid': user?.uid,
      'provider': user?.providerData.map((p) => p.providerId).join(','),
      'ms': DateTime.now().difference(t0).inMilliseconds,
      'route': route,
    });
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
            const SizedBox(height: 10),
            // TEMPORARY build marker (closed testing) — lets the tester confirm
            // at a glance which build is actually installed. Remove later.
            _rise(0.6, 1.0,
                Text(kBuildTag,
                    style: AppType.inter(11, color: DarkTokens.muted(.5)))),
          ],
        ),
      ),
    );
  }
}
