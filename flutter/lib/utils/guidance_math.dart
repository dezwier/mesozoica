import 'dart:math' as math;

/// Pure helpers for guidance distance readout and direction range glow.
class GuidanceMath {
  GuidanceMath._();

  /// Exactness → distance bucket step (meters). Piecewise-linear between keys.
  static const distanceRoundLadder = <(double, double)>[
    (0.0, 200),
    (0.125, 150),
    (0.25, 100),
    (0.375, 75),
    (0.50, 50),
    (0.625, 35),
    (0.75, 25),
    (0.875, 10),
    (0.95, 5),
    (1.0, 1),
  ];

  /// Bucket step in meters for [exactness] in 0..1.
  static double distanceStepM(double exactness) {
    final e = exactness.clamp(0.0, 1.0);
    final ladder = distanceRoundLadder;
    if (e <= ladder.first.$1) return ladder.first.$2;
    if (e >= ladder.last.$1) return ladder.last.$2;
    for (var i = 0; i < ladder.length - 1; i++) {
      final (e0, s0) = ladder[i];
      final (e1, s1) = ladder[i + 1];
      if (e <= e1) {
        final t = (e - e0) / (e1 - e0);
        return s0 + (s1 - s0) * t;
      }
    }
    return ladder.last.$2;
  }

  /// Format distance as a numeric band (or precise meters at step 1).
  static String formatDistance({
    required double distanceM,
    required double exactness,
  }) {
    final step = distanceStepM(exactness);
    if (step <= 1.0) {
      return _formatMeters(distanceM);
    }
    final low = (distanceM / step).floor() * step;
    final high = low + step;
    return '${_formatBandEdge(low)}–${_formatBandEdge(high)}'
        '${_bandUnit(low, high)}';
  }

  /// Full arc width in degrees for direction [exactness].
  static double directionRangeWidthDeg({
    required double exactness,
    double maxDeg = 180,
    double minDeg = 4,
  }) {
    final e = exactness.clamp(0.0, 1.0);
    return maxDeg * (1.0 - e) + minDeg * e;
  }

  /// Interpolate between previous and next center offsets.
  static double lerpOffsetDeg({
    required double fromDeg,
    required double toDeg,
    required double t,
  }) {
    final clamped = t.clamp(0.0, 1.0);
    return fromDeg + (toDeg - fromDeg) * clamped;
  }

  /// Random offset so true bearing stays inside a range of width [2 * halfWidthDeg].
  static double sampleRangeCenterOffsetDeg({
    required double halfWidthDeg,
    math.Random? random,
  }) {
    if (halfWidthDeg <= 0) return 0;
    final rng = random ?? math.Random();
    return (rng.nextDouble() * 2 - 1) * halfWidthDeg;
  }

  /// Screen-relative arc center (0 = device forward).
  static double rangeCenterScreenDeg({
    required double trueBearingDeg,
    required double deviceHeadingDeg,
    required double centerOffsetDeg,
  }) {
    return _normalizeDeg(trueBearingDeg + centerOffsetDeg - deviceHeadingDeg);
  }

  static double _normalizeDeg(double deg) {
    var d = deg % 360;
    if (d > 180) d -= 360;
    if (d <= -180) d += 360;
    return d;
  }

  static String _bandUnit(double low, double high) {
    if (low >= 1000 && high >= 1000) return ' km';
    return ' m';
  }

  static String _formatBandEdge(double meters) {
    if (meters >= 1000) {
      final km = meters / 1000;
      if (km >= 10) return km.toStringAsFixed(0);
      if (km == km.roundToDouble()) return km.toStringAsFixed(0);
      return km.toStringAsFixed(1);
    }
    final rounded = meters.round();
    return '$rounded';
  }

  static String _formatMeters(double meters) {
    if (meters >= 1000) {
      final km = meters / 1000;
      final label = km >= 10 ? km.toStringAsFixed(0) : km.toStringAsFixed(1);
      return '$label km';
    }
    return '${meters.round()} m';
  }
}
