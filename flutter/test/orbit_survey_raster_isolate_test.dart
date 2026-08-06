import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/widgets/map/orbit_survey_raster.dart';

void main() {
  test('isolate payload round-trips and PNG has signature', () {
    final request = OrbitSurveyRasterRequest(
      originLat: 50.0,
      originLon: 4.0,
      rangeM: 500,
      accuracy: 0.5,
      sites: const [
        OrbitSurveySiteSample(lat: 50.001, lon: 4.001, period: 'jurassic'),
        OrbitSurveySiteSample(lat: 49.999, lon: 3.999, period: 'triassic'),
      ],
      gridSize: 32,
      colors: const OrbitSurveyRasterColors(
        cretaceous: (200, 100, 50),
        jurassic: (50, 150, 80),
        triassic: (80, 60, 160),
      ),
    );

    final result = buildOrbitSurveyPngIsolate(request.toIsolatePayload());
    final raster = orbitSurveyResultFromIsolate(result);
    expect(raster.width, 32);
    expect(raster.height, 32);
    expect(raster.pngBytes, isNotNull);
    expect(raster.pngBytes!.length, greaterThan(8));
    // PNG signature
    expect(raster.pngBytes!.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
  });

  test('encodeRgbaToPng produces valid signature for empty pixels', () {
    final rgba = Uint8List(4 * 4 * 4);
    final png = encodeRgbaToPng(rgba, 4, 4);
    expect(png[0], 137);
    expect(png[1], 80);
    expect(png[2], 78);
    expect(png[3], 71);
  });
}
