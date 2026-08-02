import 'dart:math' as math;

/// Keys for the five site odd_* axes shown on the site card.
enum SiteDimensionKey {
  dino,
  fossil,
  completeness,
  quality,
  depth,
}

/// Resolved blurry range for one site dimension axis.
class SiteDimensionDisplay {
  const SiteDimensionDisplay({
    required this.rangeStart,
    required this.rangeEnd,
    required this.blurSigma,
    required this.effectiveAccuracy,
  });

  /// Inclusive low end of the uncertainty band on the unit axis.
  final double rangeStart;

  /// Inclusive high end of the uncertainty band on the unit axis.
  final double rangeEnd;

  /// Visual blur for the band; 0 when fully accurate.
  final double blurSigma;

  /// Accuracy after depth-zero bypass, clamped to [0, 1].
  final double effectiveAccuracy;

  /// Band width on the unit axis.
  double get rangeWidth => (rangeEnd - rangeStart).clamp(0.0, 1.0);

  /// True when the band collapses to a precise point.
  bool get isPrecise => rangeWidth <= 1e-6 && blurSigma <= 1e-6;
}

/// Max band width (fraction of axis) when accuracy is 0.
const double kSiteDimensionMaxRangeWidth = 1.0;

/// Max center jitter (fraction of axis) when accuracy is 0.
const double kSiteDimensionMaxCenterJitter = 0.45;

/// Blur sigma (logical px) when accuracy is 0.
const double kSiteDimensionMaxBlurSigma = 16.0;

/// Depth values at/near surface are always shown precisely (in situ).
const double kSiteDimensionDepthPreciseEpsilon = 1e-9;

/// Compute a stable, accuracy-aware blurry range for one site dimension.
///
/// - [accuracy] 0 → nearly full-axis wide band + heavy blur (true value obscured)
/// - [accuracy] 1 → sharp band collapsed to [trueValue]
/// - Depth with [trueValue] ≈ 0 is always precise, ignoring [accuracy]
SiteDimensionDisplay resolveSiteDimensionDisplay({
  required SiteDimensionKey dimension,
  required double trueValue,
  required double accuracy,
  required int siteId,
}) {
  final clampedTrue = trueValue.clamp(0.0, 1.0);
  final isDepthSurface = dimension == SiteDimensionKey.depth &&
      clampedTrue <= kSiteDimensionDepthPreciseEpsilon;
  final effectiveAccuracy =
      isDepthSurface ? 1.0 : accuracy.clamp(0.0, 1.0);
  final uncertainty = 1.0 - effectiveAccuracy;

  if (uncertainty <= 0) {
    return SiteDimensionDisplay(
      rangeStart: clampedTrue,
      rangeEnd: clampedTrue,
      blurSigma: 0.0,
      effectiveAccuracy: effectiveAccuracy,
    );
  }

  final rng = math.Random(Object.hash(siteId, dimension.index));
  final centerJitter =
      (rng.nextDouble() * 2.0 - 1.0) * uncertainty * kSiteDimensionMaxCenterJitter;
  final center = (clampedTrue + centerJitter).clamp(0.0, 1.0);

  // Seeded asymmetric split so the band is not always centered on the true value.
  final totalWidth = uncertainty * kSiteDimensionMaxRangeWidth;
  final leftFrac = 0.2 + rng.nextDouble() * 0.6; // [0.2, 0.8]
  var start = center - totalWidth * leftFrac;
  var end = center + totalWidth * (1.0 - leftFrac);

  // Keep width when clamping against axis edges.
  if (start < 0) {
    end = (end - start).clamp(0.0, 1.0);
    start = 0.0;
  }
  if (end > 1) {
    start = (start - (end - 1.0)).clamp(0.0, 1.0);
    end = 1.0;
  }

  return SiteDimensionDisplay(
    rangeStart: start,
    rangeEnd: end,
    blurSigma: uncertainty * kSiteDimensionMaxBlurSigma,
    effectiveAccuracy: effectiveAccuracy,
  );
}
