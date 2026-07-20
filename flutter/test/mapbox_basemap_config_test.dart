import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/config/map_config.dart';
import 'package:mesozoica/widgets/map/mapbox_basemap_config.dart';

void main() {
  group('MapboxBasemapConfig.lightPresetForDateTime clock fallback', () {
    test('dawn morning', () {
      expect(
        MapboxBasemapConfig.lightPresetForDateTime(DateTime(2026, 7, 20, 6)),
        'dawn',
      );
    });

    test('day midday', () {
      expect(
        MapboxBasemapConfig.lightPresetForDateTime(DateTime(2026, 7, 20, 12)),
        'day',
      );
    });

    test('dusk evening', () {
      expect(
        MapboxBasemapConfig.lightPresetForDateTime(DateTime(2026, 7, 20, 19)),
        'dusk',
      );
    });

    test('night late', () {
      expect(
        MapboxBasemapConfig.lightPresetForDateTime(DateTime(2026, 7, 20, 23)),
        'night',
      );
      expect(
        MapboxBasemapConfig.lightPresetForDateTime(DateTime(2026, 7, 20, 2)),
        'night',
      );
    });
  });

  group('MapboxBasemapConfig.lightPresetForDateTime solar', () {
    test('summer 19:00 local still day in Brussels', () {
      // 19:00 CEST = 17:00 UTC
      expect(
        MapboxBasemapConfig.lightPresetForDateTime(
          DateTime.utc(2026, 7, 20, 17),
          latitude: 50.85,
          longitude: 4.35,
        ),
        'day',
      );
    });
  });

  group('MapboxBasemapConfig.styleConfig', () {
    test('monochrome theme and all labels off', () {
      final config = MapboxBasemapConfig.styleConfig(
        lightPreset: 'dusk',
      );
      expect(config['theme'], 'monochrome');
      expect(config['theme'], MapConfig.mapboxBasemapTheme);
      expect(config['lightPreset'], 'dusk');
      expect(config['showPlaceLabels'], false);
      expect(config['showRoadLabels'], false);
      expect(config['showPointOfInterestLabels'], false);
      expect(config['showTransitLabels'], false);
      expect(config['showLandmarkIcons'], false);
      expect(config['showIndoorLabels'], false);
    });
  });
}
