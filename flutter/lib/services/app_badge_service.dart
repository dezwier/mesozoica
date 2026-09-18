import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';

/// Syncs the OS app-icon badge with the in-app unread notification count.
class AppBadgeService {
  AppBadgeService._();

  static const MethodChannel _channel = MethodChannel('mesozoica/app_badge');

  /// Sets the launcher/home-screen badge to [count] (0 clears it).
  static Future<void> setBadgeCount(int count) async {
    if (kIsWeb) return;
    if (!(defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android)) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setBadgeCount', count < 0 ? 0 : count);
    } catch (_) {
      // Native channel unavailable (e.g. tests / unsupported platform).
    }
  }
}
