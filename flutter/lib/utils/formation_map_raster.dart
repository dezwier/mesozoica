import 'dart:math' as math;
import 'dart:typed_data';

/// Compact site sample for mosaic generation.
class FormationMapSiteSample {
  const FormationMapSiteSample({
    required this.lat,
    required this.lon,
    required this.period,
  });

  final double lat;
  final double lon;
  final String period;
}

class FormationMapRasterColors {
  const FormationMapRasterColors({
    required this.cretaceous,
    required this.jurassic,
    required this.triassic,
  });

  final (int, int, int) cretaceous;
  final (int, int, int) jurassic;
  final (int, int, int) triassic;

  (int, int, int) forPeriod(String period) {
    switch (period.toLowerCase()) {
      case 'jurassic':
        return jurassic;
      case 'triassic':
        return triassic;
      case 'cretaceous':
      default:
        return cretaceous;
    }
  }
}

class FormationMapRasterRequest {
  const FormationMapRasterRequest({
    required this.originLat,
    required this.originLon,
    required this.rangeM,
    required this.accuracy,
    required this.sites,
    this.gridSize = 128,
    this.baseAlpha = 0.48,
    this.rangeFade = 0.55,
    this.boundaryBlur = 0.7,
    required this.colors,
  });

  final double originLat;
  final double originLon;
  final double rangeM;
  final double accuracy;
  final List<FormationMapSiteSample> sites;
  final int gridSize;
  final double baseAlpha;
  /// Outer fraction of the circle that fades to transparent (0–1).
  final double rangeFade;
  /// Softness of period borders (0–1); accuracy still sharpens further.
  final double boundaryBlur;
  final FormationMapRasterColors colors;
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
  });

  final int width;
  final int height;
  /// Straight (non-premultiplied) RGBA — encode to PNG before Mapbox update.
  final Uint8List rgba;
  final double west;
  final double east;
  final double south;
  final double north;

  /// ImageSource corner order: top-left, top-right, bottom-right, bottom-left.
  List<List<double>> get coordinates => [
        [west, north],
        [east, north],
        [east, south],
        [west, south],
      ];
}

/// Build a period-mosaic RGBA raster for Mapbox ImageSource (PNG-encoded later).
FormationMapRasterResult buildFormationMapRaster(
  FormationMapRasterRequest request,
) {
  final size = request.gridSize.clamp(32, 256);
  final rangeM = math.max(1.0, request.rangeM);
  final accuracy = request.accuracy.clamp(0.0, 1.0);
  final rangeFade = request.rangeFade.clamp(0.0, 1.0);
  final boundaryBlur = request.boundaryBlur.clamp(0.0, 1.0);
  final originLat = request.originLat;
  final originLon = request.originLon;

  final metersPerDegLat = 111320.0;
  final cosLat = math.cos(originLat * math.pi / 180.0).abs().clamp(0.2, 1.0);
  final metersPerDegLon = metersPerDegLat * cosLat;
  final dLat = rangeM / metersPerDegLat;
  final dLon = rangeM / metersPerDegLon;
  final north = originLat + dLat;
  final south = originLat - dLat;
  final east = originLon + dLon;
  final west = originLon - dLon;

  final sites = <_SiteXY>[];
  for (final site in request.sites) {
    final dx = (site.lon - originLon) * metersPerDegLon;
    final dy = (site.lat - originLat) * metersPerDegLat;
    // Keep sites a bit beyond the circle so edge cells still resolve.
    if (dx * dx + dy * dy > rangeM * rangeM * 4) continue;
    final rgb = request.colors.forPeriod(site.period);
    sites.add(_SiteXY(dx: dx, dy: dy, r: rgb.$1, g: rgb.$2, b: rgb.$3));
  }

  final bytes = Uint8List(size * size * 4);
  // Softness rises with boundary_blur and falls with accuracy.
  final softness = (boundaryBlur * (1.0 - accuracy * 0.85)).clamp(0.0, 1.0);
  // High IDW power → sharp; low → soft blends.
  final power = 6.0 + (0.45 - 6.0) * softness;
  final neighborCount = (3 + (8 - 3) * softness).round().clamp(3, 8);
  // range_fade=0 → hard edge; 1 → fade from center.
  final fadeStart = rangeM * (1.0 - rangeFade);
  final baseAlpha = (request.baseAlpha * 255).round().clamp(0, 255);

  for (var row = 0; row < size; row++) {
    final tY = row / (size - 1);
    final dy = rangeM * (1.0 - 2.0 * tY); // north → south
    for (var col = 0; col < size; col++) {
      final tX = col / (size - 1);
      final dx = rangeM * (2.0 * tX - 1.0); // west → east
      final distCenter = math.sqrt(dx * dx + dy * dy);
      final offset = (row * size + col) * 4;
      if (distCenter > rangeM || sites.isEmpty) {
        bytes[offset] = 0;
        bytes[offset + 1] = 0;
        bytes[offset + 2] = 0;
        bytes[offset + 3] = 0;
        continue;
      }

      var edgeFade = 1.0;
      if (rangeFade > 0 && distCenter > fadeStart) {
        final span = math.max(rangeM - fadeStart, 1e-6);
        final t = ((distCenter - fadeStart) / span).clamp(0.0, 1.0);
        // Smoothstep ease-out.
        final s = t * t * (3.0 - 2.0 * t);
        edgeFade = 1.0 - s;
      }
      final alpha = (baseAlpha * edgeFade).round().clamp(0, 255);
      if (alpha == 0) {
        bytes[offset] = 0;
        bytes[offset + 1] = 0;
        bytes[offset + 2] = 0;
        bytes[offset + 3] = 0;
        continue;
      }

      // IDW blend of nearest neighbors for soft period boundaries.
      final nearest = <(_SiteXY, double)>[];
      for (final site in sites) {
        final ddx = site.dx - dx;
        final ddy = site.dy - dy;
        final d = math.sqrt(ddx * ddx + ddy * ddy).clamp(0.5, rangeM * 4);
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
      final r = (rAcc / wSum).round().clamp(0, 255);
      final g = (gAcc / wSum).round().clamp(0, 255);
      final b = (bAcc / wSum).round().clamp(0, 255);

      bytes[offset] = r;
      bytes[offset + 1] = g;
      bytes[offset + 2] = b;
      bytes[offset + 3] = alpha;
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
