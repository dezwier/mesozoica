import 'dart:math' as math;

/// Shared fixed-world survey grid math (must match backend survey_grid.py).
/// Field ensure and Formation Map both use site_generation.lazy.cell_size_m.
const metersPerDegLat = 111320.0;

double metersPerDegLon(double lat) {
  final cosLat = math.cos(lat * math.pi / 180.0).abs().clamp(0.2, 1.0);
  return metersPerDegLat * cosLat;
}

(double, double) latLonToMeters(double lat, double lon) {
  final y = lat * metersPerDegLat;
  final x = lon * metersPerDegLon(lat);
  return (x, y);
}

(double, double) metersToLatLon(double x, double y) {
  final lat = y / metersPerDegLat;
  final lon = x / metersPerDegLon(lat);
  return (lat, lon);
}

(int, int) cellIndices(double lat, double lon, {required double cellSizeM}) {
  final (x, y) = latLonToMeters(lat, lon);
  return ((x / cellSizeM).floor(), (y / cellSizeM).floor());
}

(double, double) cellCenterLatLon(int ix, int iy, {required double cellSizeM}) {
  final x = (ix + 0.5) * cellSizeM;
  final y = (iy + 0.5) * cellSizeM;
  return metersToLatLon(x, y);
}

(double, double) snapToCellCenter(
  double lat,
  double lon, {
  required double cellSizeM,
}) {
  final (ix, iy) = cellIndices(lat, lon, cellSizeM: cellSizeM);
  return cellCenterLatLon(ix, iy, cellSizeM: cellSizeM);
}

double snapWidenessM(
  double widenessM, {
  required double cellSizeM,
  required double minWidenessM,
  required double maxWidenessM,
}) {
  final cell = cellSizeM <= 0 ? 500.0 : cellSizeM;
  final lo = math.max(minWidenessM, cell);
  final hi = math.max(maxWidenessM, lo);
  final raw = widenessM.clamp(lo, hi);
  final n = math.max(1, (raw / cell).round());
  return n * cell;
}

class GridFootprint {
  const GridFootprint({
    required this.centerLat,
    required this.centerLon,
    required this.widenessM,
    required this.cellSizeM,
    required this.n,
    required this.ix0,
    required this.ix1,
    required this.iy0,
    required this.iy1,
    required this.west,
    required this.east,
    required this.south,
    required this.north,
    required this.halfDiagonalM,
  });

  final double centerLat;
  final double centerLon;
  final double widenessM;
  final double cellSizeM;
  final int n;
  final int ix0;
  final int ix1;
  final int iy0;
  final int iy1;
  final double west;
  final double east;
  final double south;
  final double north;
  final double halfDiagonalM;

  /// Center lat/lon for every density cell inside this footprint.
  List<(double, double)> cellCenters() {
    final centers = <(double, double)>[];
    for (var ix = ix0; ix <= ix1; ix++) {
      for (var iy = iy0; iy <= iy1; iy++) {
        centers.add(cellCenterLatLon(ix, iy, cellSizeM: cellSizeM));
      }
    }
    return centers;
  }
}

GridFootprint footprintForCenter(
  double centerLat,
  double centerLon, {
  required double widenessM,
  required double cellSizeM,
}) {
  final cell = cellSizeM <= 0 ? 500.0 : cellSizeM;
  final n = math.max(1, (widenessM / cell).round());
  final sideM = n * cell;
  var (ix, iy) = cellIndices(centerLat, centerLon, cellSizeM: cell);
  final snapped = cellCenterLatLon(ix, iy, cellSizeM: cell);
  centerLat = snapped.$1;
  centerLon = snapped.$2;
  (ix, iy) = cellIndices(centerLat, centerLon, cellSizeM: cell);

  final halfLo = (n - 1) ~/ 2;
  final halfHi = n ~/ 2;
  final ix0 = ix - halfLo;
  final ix1 = ix + halfHi;
  final iy0 = iy - halfLo;
  final iy1 = iy + halfHi;

  final xWest = ix0 * cell;
  final xEast = (ix1 + 1) * cell;
  final ySouth = iy0 * cell;
  final yNorth = (iy1 + 1) * cell;

  final (swLat, swLon) = metersToLatLon(xWest, ySouth);
  final (seLat, seLon) = metersToLatLon(xEast, ySouth);
  final (nwLat, nwLon) = metersToLatLon(xWest, yNorth);
  final (neLat, neLon) = metersToLatLon(xEast, yNorth);

  return GridFootprint(
    centerLat: centerLat,
    centerLon: centerLon,
    widenessM: sideM,
    cellSizeM: cell,
    n: n,
    ix0: ix0,
    ix1: ix1,
    iy0: iy0,
    iy1: iy1,
    west: math.min(swLon, nwLon),
    east: math.max(seLon, neLon),
    south: math.min(swLat, seLat),
    north: math.max(nwLat, neLat),
    halfDiagonalM: math.sqrt(2.0) * (sideM / 2.0),
  );
}
