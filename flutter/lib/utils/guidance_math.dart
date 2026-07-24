import 'dart:math' as math;

/// Pure helpers for guidance distance readout and needle jitter.
class GuidanceMath {
  GuidanceMath._();

  static const lowExactnessMax = 0.33;
  static const midExactnessMax = 0.66;

  static const bandLabels = <String>[
    'Very close',
    'Quite close',
    'Somewhat far',
    'Quite far',
    'Very far',
  ];

  /// Format distance for the proximity overlay given [exactness] in 0..1.
  static String formatDistance({
    required double distanceM,
    required double exactness,
    List<double> bandEdgesM = const [250, 500, 750, 1000],
    double midRoundM = 100,
  }) {
    final e = exactness.clamp(0.0, 1.0);
    if (e < lowExactnessMax) {
      return bandLabel(distanceM, bandEdgesM);
    }
    if (e < midExactnessMax) {
      final step = midRoundM <= 0 ? 100.0 : midRoundM;
      final rounded = (distanceM / step).round() * step;
      return '~${_formatMeters(rounded)}';
    }
    return _formatMeters(distanceM);
  }

  static String bandLabel(double distanceM, List<double> bandEdgesM) {
    final edges = bandEdgesM.isEmpty
        ? const [250.0, 500.0, 750.0, 1000.0]
        : bandEdgesM;
    for (var i = 0; i < edges.length && i < bandLabels.length - 1; i++) {
      if (distanceM < edges[i]) return bandLabels[i];
    }
    return bandLabels[bandLabels.length - 1];
  }

  /// Peak jitter amplitude in degrees for direction [exactness].
  static double jitterAmplitudeDeg({
    required double exactness,
    required double maxJitterDeg,
  }) {
    return maxJitterDeg * (1.0 - exactness.clamp(0.0, 1.0));
  }

  /// Interpolate between previous and next jitter offsets.
  static double lerpJitterDeg({
    required double fromDeg,
    required double toDeg,
    required double t,
  }) {
    final clamped = t.clamp(0.0, 1.0);
    return fromDeg + (toDeg - fromDeg) * clamped;
  }

  /// Next random jitter offset in ±amplitude.
  static double sampleJitterDeg({
    required double amplitudeDeg,
    math.Random? random,
  }) {
    if (amplitudeDeg <= 0) return 0;
    final rng = random ?? math.Random();
    return (rng.nextDouble() * 2 - 1) * amplitudeDeg;
  }

  /// Relative needle angle (degrees) for a screen overlay around the puck.
  static double needleScreenDeg({
    required double trueBearingDeg,
    required double deviceHeadingDeg,
    required double jitterDeg,
  }) {
    return _normalizeDeg(trueBearingDeg + jitterDeg - deviceHeadingDeg);
  }

  static double _normalizeDeg(double deg) {
    var d = deg % 360;
    if (d > 180) d -= 360;
    if (d <= -180) d += 360;
    return d;
  }

  static String _formatMeters(double meters) {
    if (meters >= 1000) {
      final km = meters / 1000;
      final label = km >= 10
          ? km.toStringAsFixed(0)
          : km.toStringAsFixed(1);
      return '$label km';
    }
    return '${meters.round()} m';
  }
}
