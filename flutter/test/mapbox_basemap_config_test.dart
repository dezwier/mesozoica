import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/config/map_config.dart';
import 'package:mesozoica/widgets/map/mapbox_basemap_config.dart';

void main() {
  group('MapboxBasemapConfig.lightPresetForBrightness', () {
    test('light → day', () {
      expect(
        MapboxBasemapConfig.lightPresetForBrightness(Brightness.light),
        'day',
      );
    });

    test('dark → dusk', () {
      expect(
        MapboxBasemapConfig.lightPresetForBrightness(Brightness.dark),
        'dusk',
      );
    });
  });

  group('MapboxBasemapConfig.styleConfig', () {
    test('defaults to monochrome theme and all labels off', () {
      final config = MapboxBasemapConfig.styleConfig(
        lightPreset: 'dusk',
      );
      expect(config['theme'], 'monochrome');
      expect(config['theme'], MapConfig.mapboxBasemapTheme.value);
      expect(config['lightPreset'], 'dusk');
      expect(config['showPlaceLabels'], false);
      expect(config['showRoadLabels'], false);
      expect(config['showPointOfInterestLabels'], false);
      expect(config['showTransitLabels'], false);
      expect(config['showLandmarkIcons'], false);
      expect(config['showIndoorLabels'], false);
    });

    test('derives lightPreset from brightness when omitted', () {
      expect(
        MapboxBasemapConfig.styleConfig(brightness: Brightness.dark)['lightPreset'],
        'dusk',
      );
      expect(
        MapboxBasemapConfig.styleConfig(brightness: Brightness.light)['lightPreset'],
        'day',
      );
    });

    test('accepts explicit Mapbox theme', () {
      final config = MapboxBasemapConfig.styleConfig(
        lightPreset: 'day',
        theme: MapboxBasemapTheme.faded,
      );
      expect(config['theme'], 'faded');
    });

    test('3D objects are off by default (north-fixed is flat)', () {
      expect(
        MapboxBasemapConfig.styleConfig()['show3dObjects'],
        false,
      );
    });

    test('3D objects opt-in for rotate / AR mode', () {
      expect(
        MapboxBasemapConfig.styleConfig(show3dObjects: true)['show3dObjects'],
        true,
      );
    });
  });
}
