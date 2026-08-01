import 'dart:math' as math;
import 'dart:typed_data';

import 'orbit_survey_raster.dart' show encodeRgbaToPng;

/// Compact site sample for rock-type mosaic generation.
class FormationMapSiteSample {
  const FormationMapSiteSample({
    required this.lat,
    required this.lon,
    required this.rockType,
  });

  final double lat;
  final double lon;
  final String rockType;
}

class FormationMapRasterRequest {
  const FormationMapRasterRequest({
    required this.west,
    required this.east,
    required this.south,
    required this.north,
    required this.accuracy,
    required this.sites,
    required this.colors,
    this.gridSize = 128,
    this.baseAlpha = 0.48,
    this.boundaryBlur = 1.0,
  });

  final double west;
  final double east;
  final double south;
  final double north;
  final double accuracy;
  final List<FormationMapSiteSample> sites;
  final Map<String, (int, int, int)> colors;
  final int gridSize;
  final double baseAlpha;
  final double boundaryBlur;

  Map<String, dynamic> toIsolatePayload() {
    return {
      'west': west,
      'east': east,
      'south': south,
      'north': north,
      'accuracy': accuracy,
      'gridSize': gridSize,
      'baseAlpha': baseAlpha,
      'boundaryBlur': boundaryBlur,
      'colors': {
        for (final e in colors.entries) e.key: [e.value.$1, e.value.$2, e.value.$3],
      },
      'sites': [
        for (final site in sites) [site.lat, site.lon, site.rockType],
      ],
    };
  }

  static FormationMapRasterRequest fromIsolatePayload(
    Map<String, dynamic> payload,
  ) {
    final colorsRaw = payload['colors'] as Map<dynamic, dynamic>? ?? const {};
    final colors = <String, (int, int, int)>{};
    for (final entry in colorsRaw.entries) {
      final rgb = entry.value as List<dynamic>;
      colors[entry.key.toString()] = (
        (rgb[0] as num).toInt(),
        (rgb[1] as num).toInt(),
        (rgb[2] as num).toInt(),
      );
    }
    final sitesRaw = payload['sites'] as List<dynamic>? ?? const [];
    return FormationMapRasterRequest(
      west: (payload['west'] as num).toDouble(),
      east: (payload['east'] as num).toDouble(),
      south: (payload['south'] as num).toDouble(),
      north: (payload['north'] as num).toDouble(),
      accuracy: (payload['accuracy'] as num).toDouble(),
      gridSize: (payload['gridSize'] as num?)?.toInt() ?? 128,
      baseAlpha: (payload['baseAlpha'] as num?)?.toDouble() ?? 0.48,
      boundaryBlur: (payload['boundaryBlur'] as num?)?.toDouble() ?? 1.0,
      colors: colors,
      sites: [
        for (final row in sitesRaw)
          FormationMapSiteSample(
            lat: ((row as List<dynamic>)[0] as num).toDouble(),
            lon: (row[1] as num).toDouble(),
            rockType: row[2] as String,
          ),
      ],
    );
  }
}

class FormationMapRasterResult {
  const FormationMapRasterResult({
    required this.width,
    required this.height,
    required this.rgba,
    required this.west,
    required this.east,
    required this.south,
    required this.north,
    this.pngBytes,
  });

  final int width;
  final int height;
  final Uint8List rgba;
  final double west;
  final double east;
  final double south;
  final double north;
  final Uint8List? pngBytes;

  List<List<double>> get coordinates => [
        [west, north],
        [east, north],
        [east, south],
        [west, south],
      ];
}

Map<String, dynamic> buildFormationMapPngIsolate(Map<String, dynamic> payload) {
  final request = FormationMapRasterRequest.fromIsolatePayload(payload);
  final raster = buildFormationMapRaster(request);
  final png = encodeRgbaToPng(raster.rgba, raster.width, raster.height);
  return {
    'width': raster.width,
    'height': raster.height,
    'png': png,
    'west': raster.west,
    'east': raster.east,
    'south': raster.south,
    'north': raster.north,
  };
}

FormationMapRasterResult formationMapResultFromIsolate(
  Map<String, dynamic> result,
) {
  return FormationMapRasterResult(
    width: (result['width'] as num).toInt(),
    height: (result['height'] as num).toInt(),
    rgba: Uint8List(0),
    west: (result['west'] as num).toDouble(),
    east: (result['east'] as num).toDouble(),
    south: (result['south'] as num).toDouble(),
    north: (result['north'] as num).toDouble(),
    pngBytes: result['png'] as Uint8List,
  );
}

(int, int, int) _colorFor(
  Map<String, (int, int, int)> colors,
  String rockType,
) {
  final key = rockType.trim().toLowerCase();
  if (key.isNotEmpty && colors.containsKey(key)) return colors[key]!;
  return colors['other'] ?? (0x88, 0x88, 0x88);
}

/// Sharp rectangular rock-type IDW mosaic for Mapbox ImageSource.
FormationMapRasterResult buildFormationMapRaster(
  FormationMapRasterRequest request,
) {
  final size = request.gridSize.clamp(32, 256);
  final accuracy = request.accuracy.clamp(0.0, 1.0);
  final boundaryBlur = request.boundaryBlur.clamp(0.0, 1.0);
  final west = request.west;
  final east = request.east;
  final south = request.south;
  final north = request.north;
  final midLat = (south + north) / 2.0;
  final midLon = (west + east) / 2.0;

  final metersPerDegLat = 111320.0;
  final cosLat = math.cos(midLat * math.pi / 180.0).abs().clamp(0.2, 1.0);
  final metersPerDegLon = metersPerDegLat * cosLat;
  final widthM = ((east - west) * metersPerDegLon).abs().clamp(1.0, 1e7);
  final heightM = ((north - south) * metersPerDegLat).abs().clamp(1.0, 1e7);
  final halfW = widthM / 2.0;
  final halfH = heightM / 2.0;

  final sites = <_SiteXY>[];
  for (final site in request.sites) {
    final dx = (site.lon - midLon) * metersPerDegLon;
    final dy = (site.lat - midLat) * metersPerDegLat;
    if (dx.abs() > halfW * 2 || dy.abs() > halfH * 2) continue;
    final rgb = _colorFor(request.colors, site.rockType);
    sites.add(_SiteXY(dx: dx, dy: dy, r: rgb.$1, g: rgb.$2, b: rgb.$3));
  }

  final bytes = Uint8List(size * size * 4);
  final softness = (boundaryBlur * (1.0 - accuracy * 0.85)).clamp(0.0, 1.0);
  final power = 6.0 + (0.45 - 6.0) * softness;
  final neighborCount = (3 + (8 - 3) * softness).round().clamp(3, 8);
  final baseAlpha = (request.baseAlpha * 255).round().clamp(0, 255);
  final searchR = math.max(halfW, halfH) * 4;

  for (var row = 0; row < size; row++) {
    final tY = row / (size - 1);
    final dy = halfH * (1.0 - 2.0 * tY);
    for (var col = 0; col < size; col++) {
      final tX = col / (size - 1);
      final dx = halfW * (2.0 * tX - 1.0);
      final offset = (row * size + col) * 4;
      // Sharp rectangle: every pixel inside the bbox is opaque (no range fade).
      if (dx.abs() > halfW + 1e-6 || dy.abs() > halfH + 1e-6 || sites.isEmpty) {
        bytes[offset] = 0;
        bytes[offset + 1] = 0;
        bytes[offset + 2] = 0;
        bytes[offset + 3] = 0;
        continue;
      }

      final nearest = <(_SiteXY, double)>[];
      for (final site in sites) {
        final ddx = site.dx - dx;
        final ddy = site.dy - dy;
        final d = math.sqrt(ddx * ddx + ddy * ddy).clamp(0.5, searchR);
        nearest.add((site, d));
      }
      nearest.sort((a, b) => a.$2.compareTo(b.$2));
      final take =
          nearest.length < neighborCount ? nearest.length : neighborCount;
      var wSum = 0.0;
      var rAcc = 0.0;
      var gAcc = 0.0;
      var bAcc = 0.0;
      for (var i = 0; i < take; i++) {
        final site = nearest[i].$1;
        final d = nearest[i].$2;
        final w = 1.0 / math.pow(d, power);
        wSum += w;
        rAcc += site.r * w;
        gAcc += site.g * w;
        bAcc += site.b * w;
      }
      bytes[offset] = (rAcc / wSum).round().clamp(0, 255);
      bytes[offset + 1] = (gAcc / wSum).round().clamp(0, 255);
      bytes[offset + 2] = (bAcc / wSum).round().clamp(0, 255);
      bytes[offset + 3] = baseAlpha;
    }
  }

  return FormationMapRasterResult(
    width: size,
    height: size,
    rgba: bytes,
    west: west,
    east: east,
    south: south,
    north: north,
  );
}

class _SiteXY {
  const _SiteXY({
    required this.dx,
    required this.dy,
    required this.r,
    required this.g,
    required this.b,
  });

  final double dx;
  final double dy;
  final int r;
  final int g;
  final int b;
}
