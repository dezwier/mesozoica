import 'dart:math' as math;

/// Keys for the five site odd_* axes shown on the site card.
enum SiteDimensionKey {
  dino,
  fossil,
  completeness,
  quality,
  depth,
}

/// Resolved display position + blur for one site dimension axis.
class SiteDimensionDisplay {
  const SiteDimensionDisplay({
    required this.displayValue,
    required this.blurSigma,
    required this.effectiveAccuracy,
  });

  /// Marker position on the unit axis after seeded jitter, clamped to [0, 1].
  final double displayValue;

  /// Visual blur for the marker; 0 when fully accurate.
  final double blurSigma;

  /// Accuracy after depth-zero bypass, clamped to [0, 1].
  final double effectiveAccuracy;
}

/// Max ±jitter as a fraction of the axis when accuracy is 0.
const double kSiteDimensionMaxJitter = 0.95;

/// Blur sigma (logical px) when accuracy is 0.
const double kSiteDimensionMaxBlurSigma = 6.0;

/// Depth values at/near surface are always shown precisely.
const double kSiteDimensionDepthPreciseEpsilon = 1e-9;

/// Compute a stable, accuracy-aware display for one site dimension.
///
/// - [accuracy] 0 → nearly full-axis random + heavy blur
/// - [accuracy] 1 → exact [trueValue], no blur
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

  final jitterAmp = (1.0 - effectiveAccuracy) * kSiteDimensionMaxJitter;
  final offset = jitterAmp <= 0
      ? 0.0
      : _seededUnitOffset(siteId: siteId, dimension: dimension) * jitterAmp;
  final displayValue = (clampedTrue + offset).clamp(0.0, 1.0);
  final blurSigma = (1.0 - effectiveAccuracy) * kSiteDimensionMaxBlurSigma;

  return SiteDimensionDisplay(
    displayValue: displayValue,
    blurSigma: blurSigma,
    effectiveAccuracy: effectiveAccuracy,
  );
}

/// Deterministic offset in [-1, 1] for [siteId] + [dimension].
double _seededUnitOffset({
  required int siteId,
  required SiteDimensionKey dimension,
}) {
  final seed = Object.hash(siteId, dimension.index);
  final rng = math.Random(seed);
  return rng.nextDouble() * 2.0 - 1.0;
}
