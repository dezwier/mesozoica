import 'package:flutter_test/flutter_test.dart';

import 'package:mesozoica/utils/formation_map_raster.dart';

void main() {
  test('nearest site wins at high accuracy', () {
    final result = buildFormationMapRaster(
      FormationMapRasterRequest(
        originLat: 40.0,
        originLon: -100.0,
        rangeM: 500,
        accuracy: 1.0,
        gridSize: 64,
        sites: const [
          FormationMapSiteSample(
            lat: 40.001,
            lon: -100.0,
            period: 'triassic',
          ),
          FormationMapSiteSample(
            lat: 39.999,
            lon: -100.0,
            period: 'jurassic',
          ),
        ],
      ),
    );

    expect(result.width, 64);
    expect(result.height, 64);
    expect(result.rgbaPremultiplied.length, 64 * 64 * 4);

    // Center-north pixel should lean triassic orange (221,133,0).
    final northIdx = ((16 * 64) + 32) * 4;
    final a = result.rgbaPremultiplied[northIdx + 3];
    expect(a, greaterThan(0));
    final r = result.rgbaPremultiplied[northIdx];
    final g = result.rgbaPremultiplied[northIdx + 1];
    final b = result.rgbaPremultiplied[northIdx + 2];
    // Premultiplied — un-premultiply roughly via alpha.
    final ur = (r * 255 / a).round();
    final ug = (g * 255 / a).round();
    final ub = (b * 255 / a).round();
    expect(ur, greaterThan(180));
    expect(ug, lessThan(160));
    expect(ub, lessThan(40));
  });

  test('outside range is transparent', () {
    final result = buildFormationMapRaster(
      const FormationMapRasterRequest(
        originLat: 0,
        originLon: 0,
        rangeM: 200,
        accuracy: 0.5,
        gridSize: 32,
        sites: [
          FormationMapSiteSample(lat: 0.001, lon: 0, period: 'cretaceous'),
        ],
      ),
    );
    // Corner of AABB is outside the circle.
    expect(result.rgbaPremultiplied[3], 0);
  });

  test('low accuracy blends neighboring periods', () {
    final sharp = buildFormationMapRaster(
      FormationMapRasterRequest(
        originLat: 40.0,
        originLon: -100.0,
        rangeM: 400,
        accuracy: 1.0,
        gridSize: 48,
        sites: const [
          FormationMapSiteSample(lat: 40.001, lon: -100.0, period: 'triassic'),
          FormationMapSiteSample(lat: 39.999, lon: -100.0, period: 'jurassic'),
        ],
      ),
    );
    final soft = buildFormationMapRaster(
      FormationMapRasterRequest(
        originLat: 40.0,
        originLon: -100.0,
        rangeM: 400,
        accuracy: 0.0,
        gridSize: 48,
        sites: const [
          FormationMapSiteSample(lat: 40.001, lon: -100.0, period: 'triassic'),
          FormationMapSiteSample(lat: 39.999, lon: -100.0, period: 'jurassic'),
        ],
      ),
    );
    // Midpoint between sites (map center) should differ under soft blend.
    final mid = ((24 * 48) + 24) * 4;
    final sharpRgb = (
      sharp.rgbaPremultiplied[mid],
      sharp.rgbaPremultiplied[mid + 1],
      sharp.rgbaPremultiplied[mid + 2],
    );
    final softRgb = (
      soft.rgbaPremultiplied[mid],
      soft.rgbaPremultiplied[mid + 1],
      soft.rgbaPremultiplied[mid + 2],
    );
    expect(soft.rgbaPremultiplied[mid + 3], greaterThan(0));
    // Soft IDW should not match pure nearest-only mid color for these sites.
    expect(softRgb == sharpRgb, isFalse);
  });
}
