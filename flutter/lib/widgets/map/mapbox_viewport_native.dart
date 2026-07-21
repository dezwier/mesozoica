import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native hook: disable Mapbox `transitionsToIdleUponUserInteraction`.
///
/// FollowPuck otherwise drops to Idle on any tap; the Flutter SDK does not
/// expose ViewportOptions, so Runner/MainActivity set it on the MapView.
class MapboxViewportNative {
  MapboxViewportNative._();

  static const _channel = MethodChannel('mesozoica/mapbox_viewport');
  static bool _applied = false;

  static Future<void> disableIdleOnUserInteraction({
    int maxAttempts = 8,
  }) async {
    if (_applied) {
      // Still re-apply once — MapView can be recreated after a hot restart.
      await _invokeOnce();
      return;
    }
    for (var i = 0; i < maxAttempts; i++) {
      final count = await _invokeOnce();
      if (count > 0) {
        _applied = true;
        return;
      }
      await Future<void>.delayed(Duration(milliseconds: 80 * (i + 1)));
    }
  }

  static Future<int> _invokeOnce() async {
    try {
      final count = await _channel.invokeMethod<int>(
        'disableViewportIdleOnInteraction',
      );
      if (kDebugMode) {
        debugPrint(
          'MapboxViewportNative: disabled idle-on-interaction on ${count ?? 0} map(s)',
        );
      }
      return count ?? 0;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('MapboxViewportNative: $error');
      }
      return 0;
    }
  }
}
