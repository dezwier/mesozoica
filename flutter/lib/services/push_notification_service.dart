import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../firebase_options.dart';
import '../core/networking/api_transport.dart';
import 'api_client.dart';
import 'token_storage.dart';

/// FCM push: register device token with backend when the user is logged in.
class PushNotificationService {
  static bool _initialized = false;
  static ApiTransport transport = ApiClient.instance;

  static void debugSetTransport(ApiTransport value) {
    transport = value;
  }

  static Future<void> init() async {
    if (_initialized) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      if (!kIsWeb && Platform.isIOS) {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      FirebaseMessaging.instance.onTokenRefresh.listen((String token) {
        registerTokenWithBackend(token);
      });
      _initialized = true;
    } catch (_) {
      // Firebase not configured; push will be no-op.
    }
  }

  static Future<void> registerTokenIfLoggedIn() async {
    if (kIsWeb) return;
    final hasToken = await TokenStorage.loadToken();
    if (hasToken == null || hasToken.isEmpty) return;
    try {
      if (!_initialized) await init();
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await registerTokenWithBackend(fcmToken);
      }
    } catch (_) {
      // FCM not available or not configured.
    }
  }

  static String _getPlatform() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    return 'android';
  }

  static Future<void> registerTokenWithBackend(String fcmToken) async {
    try {
      await transport.post(
        '/api/v1/auth/device-token',
        body: {'token': fcmToken, 'platform': _getPlatform()},
      );
    } catch (_) {
      // Backend may be unreachable or auth expired; ignore.
    }
  }
}
