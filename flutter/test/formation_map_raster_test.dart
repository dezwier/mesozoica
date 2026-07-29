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
    expect(result.rgba.length, 64 * 64 * 4);

    // Center-north pixel should lean triassic orange (221,133,0).
    final northIdx = ((16 * 64) + 32) * 4;
    final a = result.rgba[northIdx + 3];
    expect(a, greaterThan(0));
    final r = result.rgba[northIdx];
    final g = result.rgba[northIdx + 1];
    final b = result.rgba[northIdx + 2];
    expect(r, greaterThan(180));
    expect(g, lessThan(160));
    expect(b, lessThan(40));
  });

  test('jurassic uses pastel green', () {
    final result = buildFormationMapRaster(
      const FormationMapRasterRequest(
        originLat: 40.0,
        originLon: -100.0,
        rangeM: 200,
        accuracy: 1.0,
        gridSize: 32,
        sites: [
          FormationMapSiteSample(lat: 40.0, lon: -100.0, period: 'jurassic'),
        ],
      ),
    );
    final mid = ((16 * 32) + 16) * 4;
    expect(result.rgba[mid + 3], greaterThan(0));
    expect(result.rgba[mid], closeTo(0xA8, 15));
    expect(result.rgba[mid + 1], closeTo(0xC9, 15));
    expect(result.rgba[mid + 2], closeTo(0xA0, 15));
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
    expect(result.rgba[3], 0);
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
      sharp.rgba[mid],
      sharp.rgba[mid + 1],
      sharp.rgba[mid + 2],
    );
    final softRgb = (
      soft.rgba[mid],
      soft.rgba[mid + 1],
      soft.rgba[mid + 2],
    );
    expect(soft.rgba[mid + 3], greaterThan(0));
    // Soft IDW should not match pure nearest-only mid color for these sites.
    expect(softRgb == sharpRgb, isFalse);
  });
}
