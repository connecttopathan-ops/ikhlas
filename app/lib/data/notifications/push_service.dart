import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../repositories/application_repository.dart';

/// Registers this device for decision/stage push notifications.
/// Called from contexts where a notification is the promised next step
/// (review-wait) and from the signed-in resting state (home) — never
/// before login, so the permission ask always has context.
class PushService {
  static bool _registered = false;

  static Future<void> register(ApplicationRepository repo) async {
    if (_registered || FirebaseAuth.instance.currentUser == null) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await messaging.getToken();
      if (token != null) await repo.saveFcmToken(token);
      messaging.onTokenRefresh.listen((t) => repo.saveFcmToken(t));
      _registered = true;
    } catch (_) {
      // Notifications are an enhancement — never break the flow over them.
    }
  }
}
