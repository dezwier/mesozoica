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
  ///
  /// [show3dObjects] is only worth paying for in rotate / AR mode: extruded
  /// buildings and their shadows are invisible at pitch 0 but still cost
  /// geometry and fragment work every frame.
  static Map<String, Object> styleConfig({
    String? lightPreset,
    MapboxBasemapTheme? theme,
    Brightness brightness = Brightness.light,
    bool show3dObjects = false,
  }) {
    return {
      'theme': (theme ?? MapConfig.mapboxBasemapTheme).value,
      'lightPreset':
          lightPreset ?? lightPresetForBrightness(brightness),
      'show3dObjects': show3dObjects,
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
    bool show3dObjects = false,
  }) {
    return map.style.setStyleImportConfigProperties(
      importId,
      styleConfig(
        lightPreset: lightPreset,
        theme: theme,
        brightness: brightness,
        show3dObjects: show3dObjects,
      ),
    );
  }
}
