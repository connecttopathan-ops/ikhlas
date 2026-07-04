import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/onboarding/landing_screen.dart';
import '../../features/onboarding/login_screen.dart';
import '../../features/onboarding/phone_capture_screen.dart';
import '../../features/gate/declaration_screen.dart';
import '../../features/gate/questionnaire/questionnaire_screen.dart';
import '../../features/gate/review_wait_screen.dart';
import '../../features/gate/decision_screens.dart';
import '../../providers/application_provider.dart';

/// Router with status-based guards (ikhlas-tech-requirements.md §4):
/// an "applying" user can never deep-link past the gate, and once the
/// gate decides, users are pinned to their decision surface.
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = RouterNotifier(ref);
  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final loc = state.matchedLocation;
      const publicRoutes = {'/', '/landing', '/login'};

      if (user == null) {
        return publicRoutes.contains(loc) ? null : '/landing';
      }

      // Signed in: gate status drives where you're allowed to be.
      final status = ref.read(userStatusProvider);
      switch (status) {
        case 'under_review':
          return loc == '/review-wait' ? null : '/review-wait';
        case 'approved':
          return (loc == '/welcome' || loc == '/profile-builder')
              ? null
              : '/welcome';
        case 'soft_rejected':
          return loc == '/decision' ? null : '/decision';
        default:
          // 'applying' (or doc still loading): the application flow is fine,
          // decision surfaces are not. /review-wait stays reachable — right
          // after submission the client lands there while the gate engine
          // is still flipping status server-side.
          const gated = {'/welcome', '/profile-builder', '/decision'};
          return gated.contains(loc) ? '/landing' : null;
      }
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/landing', builder: (_, __) => const LandingScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/phone', builder: (_, __) => const PhoneCaptureScreen()),
      GoRoute(path: '/declaration', builder: (_, __) => const DeclarationScreen()),
      GoRoute(path: '/questionnaire', builder: (_, __) => const QuestionnaireScreen()),
      GoRoute(path: '/review-wait', builder: (_, __) => const ReviewWaitScreen()),
      GoRoute(path: '/welcome', builder: (_, __) => const ApprovedScreen()),
      GoRoute(path: '/decision', builder: (_, __) => const SoftRejectedScreen()),
      GoRoute(path: '/profile-builder', builder: (_, __) => const ProfileBuilderPlaceholder()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Re-runs the router redirect whenever auth or the user doc changes —
/// this is how a gate decision made server-side moves the UI in realtime.
class RouterNotifier extends ChangeNotifier {
  RouterNotifier(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(userDocProvider, (_, __) => notifyListeners());
  }
}
