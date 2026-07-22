import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../config/map_config.dart';

/// Mapbox Standard basemap look for Mesozoica field / rotate mode.
class MapboxBasemapConfig {
  MapboxBasemapConfig._();

  static const String importId = 'basemap';

  /// Day / dusk for Mapbox `lightPreset`, matching the app appearance theme.
  static String lightPresetForBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? 'dusk' : 'day';
  }

  /// Config properties applied to the Standard `basemap` import.
  static Map<String, Object> styleConfig({
    String? lightPreset,
    MapboxBasemapTheme? theme,
    Brightness brightness = Brightness.light,
  }) {
    return {
      'theme': (theme ?? MapConfig.mapboxBasemapTheme).value,
      'lightPreset':
          lightPreset ?? lightPresetForBrightness(brightness),
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
    String? lightPreset,
    MapboxBasemapTheme? theme,
    Brightness brightness = Brightness.light,
  }) {
    return map.style.setStyleImportConfigProperties(
      importId,
      styleConfig(
        lightPreset: lightPreset,
        theme: theme,
        brightness: brightness,
      ),
    );
  }
}
