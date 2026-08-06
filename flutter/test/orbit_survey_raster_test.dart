import 'package:flutter_test/flutter_test.dart';

import 'package:mesozoica/widgets/map/orbit_survey_raster.dart';

import 'helpers/game_config_test_helpers.dart';
import 'package:mesozoica/config/game_config.dart';

void main() {
  late OrbitSurveyRasterColors palette;

  setUp(() async {
    GameConfig.debugReset();
    await loadGameConfigForTest();
    final c = GameConfig.instance.periodColors.orbitSurvey;
    palette = OrbitSurveyRasterColors(
      cretaceous: c.cretaceous,
      jurassic: c.jurassic,
      triassic: c.triassic,
    );
  });

  tearDown(GameConfig.debugReset);

  test('nearest site wins at high accuracy', () {
    final result = buildOrbitSurveyRaster(
      OrbitSurveyRasterRequest(
        originLat: 40.0,
        originLon: -100.0,
        rangeM: 500,
        accuracy: 1.0,
        gridSize: 64,
        colors: palette,
        sites: const [
          OrbitSurveySiteSample(lat: 40.001, lon: -100.0, period: 'triassic'),
          OrbitSurveySiteSample(lat: 39.999, lon: -100.0, period: 'jurassic'),
        ],
      ),
    );

    expect(result.width, 64);
    expect(result.height, 64);
    expect(result.rgba.length, 64 * 64 * 4);

    // Center-north pixel should lean triassic orange.
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

  test('jurassic uses orbit_survey palette green', () {
    final result = buildOrbitSurveyRaster(
      OrbitSurveyRasterRequest(
        originLat: 40.0,
        originLon: -100.0,
        rangeM: 200,
        accuracy: 1.0,
        gridSize: 32,
        colors: palette,
        sites: const [
          OrbitSurveySiteSample(lat: 40.0, lon: -100.0, period: 'jurassic'),
        ],
      ),
    );
    final mid = ((16 * 32) + 16) * 4;
    expect(result.rgba[mid + 3], greaterThan(0));
    expect(result.rgba[mid], closeTo(palette.jurassic.$1, 20));
    expect(result.rgba[mid + 1], closeTo(palette.jurassic.$2, 20));
    expect(result.rgba[mid + 2], closeTo(palette.jurassic.$3, 20));
  });

  test('outside range is transparent', () {
    final result = buildOrbitSurveyRaster(
      OrbitSurveyRasterRequest(
        originLat: 0,
        originLon: 0,
        rangeM: 200,
        accuracy: 0.5,
        gridSize: 32,
        colors: palette,
        sites: const [
          OrbitSurveySiteSample(lat: 0.001, lon: 0, period: 'cretaceous'),
        ],
      ),
    );
    // Corner of AABB is outside the circle.
    expect(result.rgba[3], 0);
  });

  test('low accuracy blends neighboring periods', () {
    final sharp = buildOrbitSurveyRaster(
      OrbitSurveyRasterRequest(
        originLat: 40.0,
        originLon: -100.0,
        rangeM: 400,
        accuracy: 1.0,
        gridSize: 48,
        colors: palette,
        sites: const [
          OrbitSurveySiteSample(lat: 40.001, lon: -100.0, period: 'triassic'),
          OrbitSurveySiteSample(lat: 39.999, lon: -100.0, period: 'jurassic'),
        ],
      ),
    );
    final soft = buildOrbitSurveyRaster(
      OrbitSurveyRasterRequest(
        originLat: 40.0,
        originLon: -100.0,
        rangeM: 400,
        accuracy: 0.0,
        gridSize: 48,
        colors: palette,
        sites: const [
          OrbitSurveySiteSample(lat: 40.001, lon: -100.0, period: 'triassic'),
          OrbitSurveySiteSample(lat: 39.999, lon: -100.0, period: 'jurassic'),
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
    final softRgb = (soft.rgba[mid], soft.rgba[mid + 1], soft.rgba[mid + 2]);
    expect(soft.rgba[mid + 3], greaterThan(0));
    // Soft IDW should not match pure nearest-only mid color for these sites.
    expect(softRgb == sharpRgb, isFalse);
  });
}
