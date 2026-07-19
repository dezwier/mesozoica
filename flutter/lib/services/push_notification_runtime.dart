import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import '../firebase_options.dart';

/// Background handler for FCM messages.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {
    // If Firebase can't initialize, don't crash the background isolate.
  }
}

class PushNotificationRuntime {
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) {
      _initialized = true;
      return;
    }

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _requestRuntimeNotificationPermissionIfNeeded();
    await _configureIosForegroundPresentation();

    _initialized = true;
  }

  static Future<void> _requestRuntimeNotificationPermissionIfNeeded() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await Permission.notification.request();
      } catch (_) {}
    }
  }

  static Future<void> _configureIosForegroundPresentation() async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
    } catch (_) {}
  }
}
