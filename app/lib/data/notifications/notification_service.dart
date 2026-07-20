import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

/// Displays notifications while the app is in the FOREGROUND and routes taps.
///
/// Android/iOS suppress an FCM `notification` payload when the app is
/// foregrounded (the system tray only shows it in the background), so without
/// this the user sees nothing while actually using the app. We listen to
/// [FirebaseMessaging.onMessage] and render a heads-up notification ourselves.
///
/// Token registration + permission live in [PushService]; this class is only
/// about *showing* what arrives and reacting to taps.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;
  static GoRouter? _router;

  // A single high-importance channel drives heads-up banners on Android 8+.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'ikhlaas_default',
    'Ikhlaas',
    description: 'Matches, messages, and photo requests',
    importance: Importance.high,
  );

  /// The router is created inside a Riverpod provider, so the app hands it to
  /// us once it exists; taps before then simply open the app with no nav.
  static void attachRouter(GoRouter router) => _router = router;

  static Future<void> initialize() async {
    if (_inited) return;
    _inited = true;

    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) => _route(resp.payload),
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Foreground pushes → show them ourselves.
    FirebaseMessaging.onMessage.listen(_showForeground);
    // Tapped from the tray while backgrounded, or cold-started by a tap.
    FirebaseMessaging.onMessageOpenedApp
        .listen((m) => _route(m.data['route'] as String?));
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _route(initial.data['route'] as String?);
  }

  static Future<void> _showForeground(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;
    await _local.show(
      n.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: message.data['route'] as String?,
    );
  }

  /// Route a tap. Server messages may carry `data.route`; otherwise we open
  /// the conversations list, the most likely thing a notification is about.
  static void _route(String? route) {
    final r = _router;
    if (r == null) return;
    r.go((route != null && route.isNotEmpty) ? route : '/conversations');
  }
}
