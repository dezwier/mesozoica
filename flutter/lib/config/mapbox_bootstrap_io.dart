import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'map_config.dart';

/// [MapboxOptions.setAccessToken] is fire-and-forget async. Wait until the
/// native side actually has the token before any MapWidget is created.
Future<void> configureMapboxAccessToken() async {
  if (!MapConfig.hasMapboxAccessToken) {
    if (kDebugMode) {
      debugPrint(
        'Mapbox: MAPBOX_ACCESS_TOKEN not set — rotate/3D map disabled. '
        'Pass --dart-define-from-file=.dart_defines.json',
      );
    }
    return;
  }
  final token = MapConfig.mapboxAccessToken;
  MapboxOptions.setAccessToken(token);
  for (var i = 0; i < 40; i++) {
    try {
      final current = await MapboxOptions.getAccessToken();
      if (current == token) {
        if (kDebugMode) {
          debugPrint('Mapbox: access token ready (len=${token.length})');
        }
        return;
      }
    } catch (_) {
      // Platform channel may not be ready yet on the first ticks.
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  if (kDebugMode) {
    debugPrint('Mapbox: timed out waiting for access token acknowledgement');
  }
}
