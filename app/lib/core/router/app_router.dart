import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/onboarding/landing_screen.dart';
import '../../features/onboarding/login_screen.dart';
import '../../features/onboarding/phone_capture_screen.dart';
import '../../features/gate/declaration_screen.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// Router with status-based guards: an unauthenticated user can never
/// deep-link past login. Gate-stage guards (status: applying/approved/etc.)
/// extend this redirect in Week 2 when the questionnaire lands.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final publicRoutes = {'/', '/landing', '/login'};
      if (user == null && !publicRoutes.contains(state.matchedLocation)) {
        return '/landing';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/landing', builder: (_, __) => const LandingScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/phone', builder: (_, __) => const PhoneCaptureScreen()),
      GoRoute(path: '/declaration', builder: (_, __) => const DeclarationScreen()),
      // Week 2: /questionnaire (A–E), /verify, /review-wait, /decision
      GoRoute(path: '/questionnaire', builder: (_, __) => const ComingNextWeek()),
    ],
  );
});

/// Temporary Week-2 placeholder so the Week-1 flow completes end-to-end.
class ComingNextWeek extends StatelessWidget {
  const ComingNextWeek({super.key});
  @override
  Widget build(BuildContext context) => IkhlasScaffold(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const GirihMark(size: 64, opacity: .8),
            const SizedBox(height: 20),
            Text('Questionnaire — Week 2',
                style: AppType.fraunces(22, color: DarkTokens.ivory)),
            const SizedBox(height: 8),
            Text('Declaration saved. The gate continues here next.',
                style: AppType.inter(13, color: DarkTokens.muted())),
          ]),
        ),
      );
}
