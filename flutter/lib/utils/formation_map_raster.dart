import 'dart:math' as math;
import 'dart:typed_data';

/// Compact site sample for isolate-friendly mosaic generation.
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

class FormationMapRasterRequest {
  const FormationMapRasterRequest({
    required this.originLat,
    required this.originLon,
    required this.rangeM,
    required this.accuracy,
    required this.sites,
    this.gridSize = 128,
    this.baseAlpha = 0.55,
  });

  final double originLat;
  final double originLon;
  final double rangeM;
  final double accuracy;
  final List<FormationMapSiteSample> sites;
  final int gridSize;
  final double baseAlpha;
}

class FormationMapRasterResult {
  const FormationMapRasterResult({
    required this.width,
    required this.height,
    required this.rgbaPremultiplied,
    required this.west,
    required this.east,
    required this.south,
    required this.north,
  });

  final int width;
  final int height;
  final Uint8List rgbaPremultiplied;
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

/// Cretaceous marker brown (light theme primary).
const int _cretaceousR = 0x8D;
const int _cretaceousG = 0x6E;
const int _cretaceousB = 0x63;

/// Jurassic gray.
const int _jurassicR = 195;
const int _jurassicG = 195;
const int _jurassicB = 195;

/// Triassic orange.
const int _triassicR = 221;
const int _triassicG = 133;
const int _triassicB = 0;

/// Build a period-mosaic RGBA raster (premultiplied) for Mapbox ImageSource.
FormationMapRasterResult buildFormationMapRaster(
  FormationMapRasterRequest request,
) {
  final size = request.gridSize.clamp(32, 256);
  final rangeM = math.max(1.0, request.rangeM);
  final accuracy = request.accuracy.clamp(0.0, 1.0);
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
    final rgb = _periodRgb(site.period);
    sites.add(_SiteXY(dx: dx, dy: dy, r: rgb.$1, g: rgb.$2, b: rgb.$3));
  }

  final bytes = Uint8List(size * size * 4);
  final power = 1.2 + accuracy * 10.8;
  final sharp = accuracy >= 0.995;
  final fadeStart = rangeM * 0.82;
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
      if (distCenter > fadeStart) {
        edgeFade = 1.0 - (distCenter - fadeStart) / (rangeM - fadeStart);
        edgeFade = edgeFade.clamp(0.0, 1.0);
      }
      final alpha = (baseAlpha * edgeFade).round().clamp(0, 255);
      if (alpha == 0) {
        bytes[offset] = 0;
        bytes[offset + 1] = 0;
        bytes[offset + 2] = 0;
        bytes[offset + 3] = 0;
        continue;
      }

      late final int r;
      late final int g;
      late final int b;
      if (sharp || sites.length == 1) {
        var best = sites.first;
        var bestD2 = double.infinity;
        for (final site in sites) {
          final ddx = site.dx - dx;
          final ddy = site.dy - dy;
          final d2 = ddx * ddx + ddy * ddy;
          if (d2 < bestD2) {
            bestD2 = d2;
            best = site;
          }
        }
        r = best.r;
        g = best.g;
        b = best.b;
      } else {
        // IDW blend of nearest neighbors (capped) for soft boundaries.
        final nearest = <(_SiteXY, double)>[];
        for (final site in sites) {
          final ddx = site.dx - dx;
          final ddy = site.dy - dy;
          final d = math.sqrt(ddx * ddx + ddy * ddy).clamp(0.5, rangeM * 4);
          nearest.add((site, d));
        }
        nearest.sort((a, b) => a.$2.compareTo(b.$2));
        final take = nearest.length < 4 ? nearest.length : 4;
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
        r = (rAcc / wSum).round().clamp(0, 255);
        g = (gAcc / wSum).round().clamp(0, 255);
        b = (bAcc / wSum).round().clamp(0, 255);
      }

      // Premultiplied RGBA.
      bytes[offset] = (r * alpha / 255).round();
      bytes[offset + 1] = (g * alpha / 255).round();
      bytes[offset + 2] = (b * alpha / 255).round();
      bytes[offset + 3] = alpha;
    }
  }

  return FormationMapRasterResult(
    width: size,
    height: size,
    rgbaPremultiplied: bytes,
    west: west,
    east: east,
    south: south,
    north: north,
  );
}

(int, int, int) _periodRgb(String period) {
  switch (period.toLowerCase()) {
    case 'jurassic':
      return (_jurassicR, _jurassicG, _jurassicB);
    case 'triassic':
      return (_triassicR, _triassicG, _triassicB);
    case 'cretaceous':
    default:
      return (_cretaceousR, _cretaceousG, _cretaceousB);
  }
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
