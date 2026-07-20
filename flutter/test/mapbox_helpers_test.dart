import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/config/map_config.dart';
import 'package:mesozoica/widgets/map/mapbox_marker_images.dart';
import 'package:mesozoica/widgets/map/mapbox_site_annotations.dart';

void main() {
  group('mapboxBearingFromHeading', () {
    test('normalizes negative headings', () {
      expect(mapboxBearingFromHeading(-90), 270);
    });

    test('wraps past 360', () {
      expect(mapboxBearingFromHeading(450), 90);
    });

    test('passes through north', () {
      expect(mapboxBearingFromHeading(0), 0);
      expect(mapboxBearingFromHeading(180), 180);
    });
  });

  group('clampMapboxZoom', () {
    test('clamps to map config range', () {
      expect(clampMapboxZoom(0), MapConfig.minZoom);
      expect(clampMapboxZoom(99), MapConfig.maxZoom);
      expect(clampMapboxZoom(10), 10);
    });
  });

  group('mapboxPitchForMode', () {
    test('fixed is flat, rotate is tilted', () {
      expect(mapboxPitchForMode(rotateWithHeading: false), 0);
      expect(
        mapboxPitchForMode(rotateWithHeading: true),
        MapConfig.mapboxFollowPitch,
      );
    });
  });

  group('mapboxMarkerImageKey', () {
    test('includes period and size', () {
      expect(
        mapboxMarkerImageKey(
          period: 'Jurassic',
          sizeBucket: 18,
        ),
        'jurassic|dot|18',
      );
    });

    test('defaults missing period', () {
      expect(
        mapboxMarkerImageKey(
          period: null,
          sizeBucket: 12,
        ),
        'default|dot|12',
      );
    });
  });

  group('mapboxMarkerSizeBucket', () {
    test('grows with zoom', () {
      final far = mapboxMarkerSizeBucket(MapConfig.minZoom);
      final near = mapboxMarkerSizeBucket(MapConfig.maxZoom);
      expect(near, greaterThan(far));
    });
  });

  group('mapboxMarkerRadiusForZoom', () {
    test('grows with zoom', () {
      expect(
        mapboxMarkerRadiusForZoom(MapConfig.maxZoom),
        greaterThan(mapboxMarkerRadiusForZoom(MapConfig.minZoom)),
      );
    });

    test('mid zoom stays closer to the small end', () {
      final far = mapboxMarkerRadiusForZoom(MapConfig.minZoom);
      final near = mapboxMarkerRadiusForZoom(MapConfig.maxZoom);
      final midZoom =
          (MapConfig.minZoom + MapConfig.maxZoom) / 2;
      final mid = mapboxMarkerRadiusForZoom(midZoom);
      final linearMid = (far + near) / 2;
      expect(mid, lessThan(linearMid));
      expect(mid, closeTo(far, (near - far) * 0.35));
    });
  });
}
