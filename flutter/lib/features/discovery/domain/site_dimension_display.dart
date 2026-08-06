import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import '../../game_config/game_config.dart';

/// Keys for the five site odd_* axes shown on the site card.
enum SiteDimensionKey { dino, fossil, completeness, quality, depth }

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

/// Deterministic per-site / per-dimension accuracy noise after skill baseline.
///
/// Must match [apply_dimension_accuracy_noise] in the backend
/// (`dimension_display.py`). Seed uses [SiteDimensionKey.index].
/// Amplitude from [AccuracyNoiseConfig] in site stewardship YAML.
double applyDimensionAccuracyNoise({
  required double baseAccuracy,
  required int siteId,
  required SiteDimensionKey dimension,
}) {
  final base = baseAccuracy.clamp(0.0, 1.0);
  final noise = GameConfig.isLoaded
      ? GameConfig.instance.siteStewardship.accuracyNoise
      : AccuracyNoiseConfig.defaults;
  final digest = md5
      .convert(utf8.encode('$siteId:${dimension.index}:acc'))
      .bytes;
  final unit =
      ByteData.sublistView(
        Uint8List.fromList(digest),
      ).getUint32(0, Endian.big) /
      0x100000000;
  final amp = noise.maxDelta;
  final delta = (unit * 2.0 - 1.0) * amp;
  return (base + delta).clamp(0.0, 1.0);
}

/// Add time-based documentation progress to skill accuracy, capped at 1.0.
double applyDocumentationProgress(
  double skillAccuracy,
  double documentationProgress,
) {
  final boost = documentationProgress.clamp(0.0, 1.0);
  return (skillAccuracy + boost).clamp(0.0, 1.0);
}

/// True when all five display accuracies are at 100%.
///
/// Mirrors backend [site_is_fully_documented] so the client can force-sync
/// the moment local progress would complete documentation.
bool siteIsFullyDocumented({
  required int siteId,
  required double? oddDinoCount,
  required double? oddFossilCount,
  required double? oddCompleteness,
  required double? oddQuality,
  required double? oddDepth,
  required int skillLevel,
  required double documentationProgress,
}) {
  const accuracyParam = 'documentation_accuracy';
  final values = <SiteDimensionKey, double?>{
    SiteDimensionKey.dino: oddDinoCount,
    SiteDimensionKey.fossil: oddFossilCount,
    SiteDimensionKey.completeness: oddCompleteness,
    SiteDimensionKey.quality: oddQuality,
    SiteDimensionKey.depth: oddDepth,
  };
  if (values.values.any((v) => v == null)) return false;

  final baseAccuracies = resolveSiteStewardshipAccuracies(
    skillLevel: skillLevel,
  );
  final skillAcc = baseAccuracies[accuracyParam] ?? 0.0;
  for (final entry in values.entries) {
    final boosted = applyDocumentationProgress(
      applyDimensionAccuracyNoise(
        baseAccuracy: skillAcc,
        siteId: siteId,
        dimension: entry.key,
      ),
      documentationProgress,
    );
    final band = resolveSiteDimensionDisplay(
      dimension: entry.key,
      trueValue: entry.value!,
      accuracy: boosted,
      siteId: siteId,
    );
    if (band.effectiveAccuracy < 1.0 - 1e-9) return false;
  }
  return true;
}

/// Aggregate live accuracy used by the documentation bar and map-marker ring.
double siteDocumentationAverageAccuracy({
  required int siteId,
  required int skillLevel,
  required double documentationProgress,
  required double? oddDepth,
  required Map<SiteDimensionKey, double> serverAccuracies,
}) {
  final skillAcc =
      resolveSiteStewardshipAccuracies(
        skillLevel: skillLevel,
      )['documentation_accuracy'] ??
      0.0;
  var total = 0.0;
  for (final dimension in SiteDimensionKey.values) {
    var effective = applyDocumentationProgress(
      applyDimensionAccuracyNoise(
        baseAccuracy: skillAcc,
        siteId: siteId,
        dimension: dimension,
      ),
      documentationProgress,
    );
    final serverAccuracy = serverAccuracies[dimension] ?? 0.0;
    if (serverAccuracy > effective) effective = serverAccuracy;
    if (dimension == SiteDimensionKey.depth &&
        oddDepth != null &&
        oddDepth <= kSiteDimensionDepthPreciseEpsilon) {
      effective = 1.0;
    }
    total += effective.clamp(0.0, 1.0);
  }
  return (total / SiteDimensionKey.values.length).clamp(0.0, 1.0);
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
  final isDepthSurface =
      dimension == SiteDimensionKey.depth &&
      clampedTrue <= kSiteDimensionDepthPreciseEpsilon;
  final effectiveAccuracy = isDepthSurface ? 1.0 : accuracy.clamp(0.0, 1.0);
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
      (rng.nextDouble() * 2.0 - 1.0) *
      uncertainty *
      kSiteDimensionMaxCenterJitter;
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
