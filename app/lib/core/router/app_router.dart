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
import '../../features/gate/verify_id_screen.dart';
import '../../features/profile/profile_builder_screen.dart';
import '../../features/profile/edit_profile_screen.dart';
import '../../features/profile/home_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/chat/conversations_screen.dart';
import '../../features/chat/chat_screen.dart';
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
      final profileComplete = ref.read(profileCompleteProvider);
      final userDoc = ref.read(userDocProvider).value?.data();
      final idRequired = userDoc?['idRequired'] == true;
      final idApproved = userDoc?['idDocStatus'] == 'approved';
      switch (status) {
        case 'under_review':
          return loc == '/review-wait' ? null : '/review-wait';
        case 'needs_info':
          // ID rejected → pinned to re-verification until approved.
          return loc == '/verify-id' ? null : '/verify-id';
        case 'approved':
        case 'paused':
          // Mandatory government-ID gate: after approval, before pool entry.
          if (idRequired && !idApproved) {
            return loc == '/verify-id' ? null : '/verify-id';
          }
          if (profileComplete) {
            final allowed = {'/home', '/settings', '/profile-builder',
              '/edit-profile', '/conversations'};
            if (allowed.contains(loc) || loc.startsWith('/chat/')) return null;
            return '/home';
          }
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
          const gated = {
            '/welcome', '/profile-builder', '/decision', '/home', '/settings',
            '/conversations'
          };
          if (gated.contains(loc) || loc.startsWith('/chat/')) return '/landing';
          return null;
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
      GoRoute(path: '/verify-id', builder: (_, __) => const VerifyIdScreen()),
      GoRoute(path: '/welcome', builder: (_, __) => const ApprovedScreen()),
      GoRoute(path: '/decision', builder: (_, __) => const SoftRejectedScreen()),
      GoRoute(path: '/profile-builder', builder: (_, __) => const ProfileBuilderScreen()),
      GoRoute(path: '/edit-profile', builder: (_, __) => const EditProfileScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/conversations', builder: (_, __) => const ConversationsScreen()),
      GoRoute(
          path: '/chat/:id',
          builder: (_, s) => ChatScreen(convId: s.pathParameters['id']!)),
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
