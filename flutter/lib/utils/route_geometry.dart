import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Haversine helpers for aerial-recon route interpolation (mirrors backend).
class RouteGeometry {
  RouteGeometry._();

  static const Distance _distance = Distance();

  static double lengthKm(List<LatLng> points) {
    if (points.length < 2) return 0;
    var metres = 0.0;
    for (var i = 1; i < points.length; i++) {
      metres += _distance(points[i - 1], points[i]);
    }
    return metres / 1000.0;
  }

  /// Point at [fraction] of total arc length (clamped to 0..1).
  static LatLng pointAtFraction(List<LatLng> points, double fraction) {
    if (points.isEmpty) {
      throw ArgumentError('route must not be empty');
    }
    if (points.length == 1) return points.first;
    final frac = fraction.clamp(0.0, 1.0);
    final total = lengthKm(points);
    if (total <= 0) return points.first;
    final targetM = total * frac * 1000.0;
    var traveled = 0.0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final seg = _distance(a, b);
      if (seg <= 0) continue;
      if (traveled + seg >= targetM) {
        final t = (targetM - traveled) / seg;
        return LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        );
      }
      traveled += seg;
    }
    return points.last;
  }

  /// Bearing degrees clockwise from north for the segment at [fraction].
  static double bearingAtFraction(List<LatLng> points, double fraction) {
    if (points.length < 2) return 0;
    final frac = fraction.clamp(0.0, 0.999);
    final here = pointAtFraction(points, frac);
    final ahead = pointAtFraction(points, math.min(1.0, frac + 0.002));
    return _distance.bearing(here, ahead);
  }
}
