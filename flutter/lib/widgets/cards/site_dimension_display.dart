import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

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
    this.trueValue,
    required this.rangeStart,
    required this.rangeEnd,
    required this.blurSigma,
    required this.effectiveAccuracy,
  });

  /// Ground-truth value on the unit axis (admin exact marker when non-null).
  final double? trueValue;

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

/// +1% accuracy per meter walked inside site_visibility_m (additive, capped).
const double kExplorationAccuracyPerM = 0.01;

/// Relative half-amplitude of per-dimension accuracy noise (±30% of baseline).
const double kSiteDimensionAccuracyNoiseRel = 0.30;

/// Floor so near-zero baselines still vary a little.
const double kSiteDimensionAccuracyNoiseMinAbs = 0.03;

/// Deterministic per-site / per-dimension accuracy noise after skill baseline.
///
/// Must match [apply_dimension_accuracy_noise] in the backend
/// (`dimension_display.py`). Seed uses [SiteDimensionKey.index].
double applyDimensionAccuracyNoise({
  required double baseAccuracy,
  required int siteId,
  required SiteDimensionKey dimension,
}) {
  final base = baseAccuracy.clamp(0.0, 1.0);
  final digest =
      md5.convert(utf8.encode('$siteId:${dimension.index}:acc')).bytes;
  final unit =
      ByteData.sublistView(Uint8List.fromList(digest)).getUint32(0, Endian.big) /
          0x100000000;
  final amp = math.max(
    kSiteDimensionAccuracyNoiseMinAbs,
    base.abs() * kSiteDimensionAccuracyNoiseRel,
  );
  final delta = (unit * 2.0 - 1.0) * amp;
  return (base + delta).clamp(0.0, 1.0);
}

/// Additive boost: skill accuracy + 1% per explored meter, capped at 1.0.
double applyExplorationAccuracyBoost(
  double skillAccuracy,
  double exploredDistanceM,
) {
  final boost = exploredDistanceM.clamp(0.0, double.infinity) *
      kExplorationAccuracyPerM;
  return (skillAccuracy + boost).clamp(0.0, 1.0);
}

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
      trueValue: clampedTrue,
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
    trueValue: clampedTrue,
    rangeStart: start,
    rangeEnd: end,
    blurSigma: uncertainty * kSiteDimensionMaxBlurSigma,
    effectiveAccuracy: effectiveAccuracy,
  );
}
