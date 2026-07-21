import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../config/map_config.dart';
import '../../utils/solar_period.dart';

/// Mapbox Standard basemap look for Mesozoica field / rotate mode.
class MapboxBasemapConfig {
  MapboxBasemapConfig._();

  static const String importId = 'basemap';

  /// Dawn / day / dusk / night for Mapbox `lightPreset`.
  ///
  /// When [latitude] and [longitude] are set, uses solar elevation (civil
  /// twilight) so seasons and location are respected. Without a location,
  /// falls back to rough civil clock windows:
  /// - night: 21:00–04:59
  /// - dawn: 05:00–07:59
  /// - day: 08:00–16:59
  /// - dusk: 17:00–20:59
  static String lightPresetForDateTime(
    DateTime local, {
    double? latitude,
    double? longitude,
  }) {
    if (latitude != null && longitude != null) {
      return Solar.lightPresetAt(
        latitude: latitude,
        longitude: longitude,
        at: local,
      );
    }
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
    MapboxBasemapTheme? theme,
    double? latitude,
    double? longitude,
  }) {
    return {
      'theme': (theme ?? MapConfig.mapboxBasemapTheme).value,
      'lightPreset': lightPreset ??
          lightPresetForDateTime(
            now ?? DateTime.now(),
            latitude: latitude,
            longitude: longitude,
          ),
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
    MapboxBasemapTheme? theme,
    double? latitude,
    double? longitude,
  }) {
    return map.style.setStyleImportConfigProperties(
      importId,
      styleConfig(
        now: now,
        lightPreset: lightPreset,
        theme: theme,
        latitude: latitude,
        longitude: longitude,
      ),
    );
  }
}
