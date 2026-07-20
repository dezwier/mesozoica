import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../config/map_config.dart';

/// Mapbox Standard basemap look for Mesozoica field / rotate mode.
class MapboxBasemapConfig {
  MapboxBasemapConfig._();

  static const String importId = 'basemap';

  /// Dawn / day / dusk / night from local clock.
  ///
  /// Rough civil windows (not solar altitude):
  /// - night: 21:00–04:59
  /// - dawn: 05:00–07:59
  /// - day: 08:00–16:59
  /// - dusk: 17:00–20:59
  static String lightPresetForDateTime(DateTime local) {
    final hour = local.hour;
    if (hour >= 5 && hour < 8) return 'dawn';
    if (hour >= 8 && hour < 17) return 'day';
    if (hour >= 17 && hour < 21) return 'dusk';
    return 'night';
  }

  /// Config properties applied to the Standard `basemap` import.
  static Map<String, Object> styleConfig({
    DateTime? now,
    String? lightPreset,
  }) {
    return {
      'theme': MapConfig.mapboxBasemapTheme,
      'lightPreset': lightPreset ?? lightPresetForDateTime(now ?? DateTime.now()),
      'showPlaceLabels': false,
      'showRoadLabels': false,
      'showPointOfInterestLabels': false,
      'showTransitLabels': false,
      'showLandmarkIcons': false,
      'showLandmarkIconLabels': false,
      'showIndoorLabels': false,
    };
  }

  static Future<void> apply(
    MapboxMap map, {
    DateTime? now,
    String? lightPreset,
  }) {
    return map.style.setStyleImportConfigProperties(
      importId,
      styleConfig(now: now, lightPreset: lightPreset),
    );
  }
}
