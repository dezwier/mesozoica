import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Compact site sample for mosaic generation.
class OrbitSurveySiteSample {
  const OrbitSurveySiteSample({
    required this.lat,
    required this.lon,
    required this.period,
  });

  final double lat;
  final double lon;
  final String period;
}

class OrbitSurveyRasterColors {
  const OrbitSurveyRasterColors({
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

class OrbitSurveyRasterRequest {
  const OrbitSurveyRasterRequest({
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
  final List<OrbitSurveySiteSample> sites;
  final int gridSize;
  final double baseAlpha;
  /// Outer fraction of the circle that fades to transparent (0–1).
  final double rangeFade;
  /// Softness of period borders (0–1); accuracy still sharpens further.
  final double boundaryBlur;
  final OrbitSurveyRasterColors colors;

  /// SendPort-safe payload for [compute] / [buildOrbitSurveyPngIsolate].
  Map<String, dynamic> toIsolatePayload() {
    return {
      'originLat': originLat,
      'originLon': originLon,
      'rangeM': rangeM,
      'accuracy': accuracy,
      'gridSize': gridSize,
      'baseAlpha': baseAlpha,
      'rangeFade': rangeFade,
      'boundaryBlur': boundaryBlur,
      'cretaceous': [
        colors.cretaceous.$1,
        colors.cretaceous.$2,
        colors.cretaceous.$3,
      ],
      'jurassic': [colors.jurassic.$1, colors.jurassic.$2, colors.jurassic.$3],
      'triassic': [colors.triassic.$1, colors.triassic.$2, colors.triassic.$3],
      'sites': [
        for (final site in sites) [site.lat, site.lon, site.period],
      ],
    };
  }

  static OrbitSurveyRasterRequest fromIsolatePayload(
    Map<String, dynamic> payload,
  ) {
    (int, int, int) rgb(List<dynamic> raw) => (
          (raw[0] as num).toInt(),
          (raw[1] as num).toInt(),
          (raw[2] as num).toInt(),
        );
    final sitesRaw = payload['sites'] as List<dynamic>? ?? const [];
    return OrbitSurveyRasterRequest(
      originLat: (payload['originLat'] as num).toDouble(),
      originLon: (payload['originLon'] as num).toDouble(),
      rangeM: (payload['rangeM'] as num).toDouble(),
      accuracy: (payload['accuracy'] as num).toDouble(),
      gridSize: (payload['gridSize'] as num?)?.toInt() ?? 128,
      baseAlpha: (payload['baseAlpha'] as num?)?.toDouble() ?? 0.48,
      rangeFade: (payload['rangeFade'] as num?)?.toDouble() ?? 0.55,
      boundaryBlur: (payload['boundaryBlur'] as num?)?.toDouble() ?? 0.7,
      colors: OrbitSurveyRasterColors(
        cretaceous: rgb(payload['cretaceous'] as List<dynamic>),
        jurassic: rgb(payload['jurassic'] as List<dynamic>),
        triassic: rgb(payload['triassic'] as List<dynamic>),
      ),
      sites: [
        for (final row in sitesRaw)
          OrbitSurveySiteSample(
            lat: ((row as List<dynamic>)[0] as num).toDouble(),
            lon: (row[1] as num).toDouble(),
            period: row[2] as String,
          ),
      ],
    );
  }
}

class OrbitSurveyRasterResult {
  const OrbitSurveyRasterResult({
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
  /// Straight (non-premultiplied) RGBA — encode to PNG before Mapbox update.
  final Uint8List rgba;
  final double west;
  final double east;
  final double south;
  final double north;
  /// Pre-encoded PNG when built via [buildOrbitSurveyPngIsolate].
  final Uint8List? pngBytes;

  /// ImageSource corner order: top-left, top-right, bottom-right, bottom-left.
  List<List<double>> get coordinates => [
        [west, north],
        [east, north],
        [east, south],
        [west, south],
      ];
}

/// Isolate entry: IDW raster + PNG encode off the UI thread.
Map<String, dynamic> buildOrbitSurveyPngIsolate(Map<String, dynamic> payload) {
  final request = OrbitSurveyRasterRequest.fromIsolatePayload(payload);
  final raster = buildOrbitSurveyRaster(request);
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

OrbitSurveyRasterResult orbitSurveyResultFromIsolate(
  Map<String, dynamic> result,
) {
  return OrbitSurveyRasterResult(
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

/// Minimal RGBA8888 → PNG (zlib) encoder safe for background isolates.
Uint8List encodeRgbaToPng(Uint8List rgba, int width, int height) {
  final rowStride = width * 4;
  final raw = Uint8List((rowStride + 1) * height);
  for (var y = 0; y < height; y++) {
    final dst = y * (rowStride + 1);
    raw[dst] = 0; // filter none
    raw.setRange(dst + 1, dst + 1 + rowStride, rgba, y * rowStride);
  }
  final compressed = ZLibEncoder().convert(raw);

  final bytes = BytesBuilder(copy: false);
  bytes.add(const [137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> data) {
    final typeCodes = type.codeUnits;
    final len = ByteData(4)..setUint32(0, data.length);
    bytes.add(len.buffer.asUint8List());
    bytes.add(typeCodes);
    bytes.add(data);
    final crc = _pngCrc([...typeCodes, ...data]);
    final crcBytes = ByteData(4)..setUint32(0, crc);
    bytes.add(crcBytes.buffer.asUint8List());
  }

  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6) // RGBA
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', compressed);
  chunk('IEND', const []);
  return bytes.toBytes();
}

int _pngCrc(List<int> data) {
  var c = 0xffffffff;
  for (final b in data) {
    c ^= b;
    for (var i = 0; i < 8; i++) {
      c = (c & 1) != 0 ? (0xedb88320 ^ (c >> 1)) : (c >> 1);
    }
  }
  return c ^ 0xffffffff;
}

/// Build a period-mosaic RGBA raster for Mapbox ImageSource (PNG-encoded later).
OrbitSurveyRasterResult buildOrbitSurveyRaster(
  OrbitSurveyRasterRequest request,
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

  return OrbitSurveyRasterResult(
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
