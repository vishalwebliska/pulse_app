import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import 'api_client.dart';
import 'push_navigation.dart';

/// Firebase Cloud Messaging push notifications.
///
/// FCM only has a native implementation on **Android, iOS and web**. On
/// Windows, macOS and Linux there is no firebase_messaging plugin, so every
/// entry point here returns immediately on those platforms. That keeps the
/// desktop builds (our local test target) compiling and crash-free — in-app
/// notifications (Reverb) already cover foreground alerts everywhere, and push
/// is only needed to wake a backgrounded/terminated Android/iOS/web client.
class PushService {
  PushService._();

  static bool _firebaseReady = false;
  static StreamSubscription<String>? _tokenRefreshSub;

  /// True only where firebase_messaging has a native implementation.
  static bool get _supported {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return true;
      default:
        return false; // Windows / macOS / Linux: no FCM plugin.
    }
  }

  /// Initialise the Firebase core SDK. Safe to call on every platform — a no-op
  /// off Android/iOS/web. Call once at startup, before `runApp`.
  static Future<void> initFirebase() async {
    if (!_supported || _firebaseReady) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _firebaseReady = true;
      await _initTapHandlers();
    } catch (_) {
      // Platform not configured in firebase_options — leave push off silently.
    }
  }

  /// Route a tapped push to the conversation (and message) it points at.
  /// Covers both entry points: the app launched cold from a notification
  /// ([getInitialMessage]) and resumed from the background by a tap
  /// ([onMessageOpenedApp]). The target is stashed in [pendingPushTarget];
  /// the shell opens it once it is mounted + signed in. No-op display here —
  /// a foregrounded message is already surfaced by the Reverb in-app path, so
  /// we deliberately do NOT listen to onMessage (that would double-alert).
  static bool _tapHandlersReady = false;
  static Future<void> _initTapHandlers() async {
    if (!_supported || _tapHandlersReady) return;
    _tapHandlersReady = true;
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _handleTap(initial);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    } catch (_) {
      // Messaging not available on this platform/build — stay silent.
    }
  }

  static void _handleTap(RemoteMessage message) {
    final target = pushTargetFromData(message.data);
    if (target != null) pendingPushTarget.value = target;
  }

  /// After sign-in: request permission, read the FCM token and register it with
  /// the backend so this device receives push. No-op on unsupported platforms,
  /// and fire-and-forget safe (never throws).
  static Future<void> registerForUser() async {
    if (!_supported) return;
    await initFirebase();
    if (!_firebaseReady) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();

      // Web push needs a VAPID key from the Firebase console (Cloud Messaging →
      // Web Push certificates), supplied at build time. Until it's provided,
      // skip web token registration rather than crash.
      if (kIsWeb && _webVapidKey.isEmpty) return;

      final token = await messaging.getToken(
        vapidKey: kIsWeb ? _webVapidKey : null,
      );
      if (token != null && token.isNotEmpty) {
        await _registerToken(token);
      }
      // Re-register whenever FCM rotates the token.
      _tokenRefreshSub ??=
          messaging.onTokenRefresh.listen((t) => _registerToken(t));
    } catch (_) {
      // Permission denied / no Play Services / APNs not ready — stay silent.
    }
  }

  static Future<void> _registerToken(String token) async {
    try {
      await ApiClient.instance.dio.post('/device-tokens', data: {
        'token': token,
        'platform': kIsWeb ? 'web' : 'fcm',
        'device_name': _deviceName,
      });
    } on DioException {
      // Not signed in yet / transient — a later refresh re-registers.
    }
  }

  static String get _deviceName {
    if (kIsWeb) return 'Pulse Web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Pulse Android';
      case TargetPlatform.iOS:
        return 'Pulse iOS';
      default:
        return 'Pulse';
    }
  }

  static const String _webVapidKey =
      String.fromEnvironment('PULSE_WEB_VAPID', defaultValue: '');
}
