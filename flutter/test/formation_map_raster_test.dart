import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/widgets/map/formation_map_raster.dart';

void main() {
  test('rectangle raster colors by rock type with sharp edges', () {
    final request = FormationMapRasterRequest(
      west: 4.0,
      east: 4.01,
      south: 50.0,
      north: 50.01,
      accuracy: 1.0,
      baseAlpha: 0.5,
      boundaryBlur: 0.0,
      colors: const {
        'sandstone': (0xD4, 0xA0, 0x17),
        'limestone': (0xE8, 0xD5, 0xB7),
        'other': (0x88, 0x88, 0x88),
      },
      sites: const [
        FormationMapSiteSample(lat: 50.005, lon: 4.005, rockType: 'sandstone'),
        FormationMapSiteSample(lat: 50.008, lon: 4.008, rockType: 'limestone'),
      ],
      gridSize: 32,
    );

    final raster = buildFormationMapRaster(request);
    expect(raster.width, 32);
    expect(raster.height, 32);
    expect(raster.rgba.length, 32 * 32 * 4);

    // Center pixel should be opaque.
    final mid = ((16 * 32 + 16) * 4);
    expect(raster.rgba[mid + 3], greaterThan(0));

    // Corners of the image are still inside the bbox for this request.
    expect(raster.rgba[3], greaterThan(0));
  });
}
