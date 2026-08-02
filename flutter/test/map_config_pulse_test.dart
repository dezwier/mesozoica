import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/config/map_config.dart';

void main() {
  test('ground radius pulse grows when zooming in', () {
    const lat = 51.0;
    const radiusM = 50.0;
    final at17 = MapConfig.groundRadiusToPulsePx(
      radiusM: radiusM,
      latitudeDeg: lat,
      zoom: 17,
    );
    final at18 = MapConfig.groundRadiusToPulsePx(
      radiusM: radiusM,
      latitudeDeg: lat,
      zoom: 18,
    );
    expect(at18, closeTo(at17 * 2, 0.5));
    // Mapbox 512px tiles: ~2× the old 256px-tile formula.
    expect(at17, greaterThan(100));
  });

  test('larger visibility distance yields larger pulse', () {
    const lat = 51.0;
    const zoom = 17.0;
    final small = MapConfig.groundRadiusToPulsePx(
      radiusM: 50,
      latitudeDeg: lat,
      zoom: zoom,
    );
    final large = MapConfig.groundRadiusToPulsePx(
      radiusM: 100,
      latitudeDeg: lat,
      zoom: zoom,
    );
    expect(large, closeTo(small * 2, 0.5));
  });

  test('Mapbox meters-per-pixel uses 512px tile constant', () {
    final mPerPx = MapConfig.metersPerPixel(latitudeDeg: 0, zoom: 0);
    expect(mPerPx, closeTo(MapConfig.mapboxMetersPerPixelAtZoom0, 1e-6));
    // Must not use the Leaflet/Google 256px constant (156543).
    expect(mPerPx, lessThan(100000));
  });
}
