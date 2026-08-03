import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/widgets/cards/site_dimension_display.dart';

void main() {
  group('resolveSiteDimensionDisplay', () {
    test('accuracy 1 collapses to a precise point with no blur', () {
      final result = resolveSiteDimensionDisplay(
        dimension: SiteDimensionKey.dino,
        trueValue: 0.42,
        accuracy: 1.0,
        siteId: 50001,
      );
      expect(result.trueValue, closeTo(0.42, 1e-9));
      expect(result.rangeStart, closeTo(0.42, 1e-9));
      expect(result.rangeEnd, closeTo(0.42, 1e-9));
      expect(result.blurSigma, 0.0);
      expect(result.effectiveAccuracy, 1.0);
      expect(result.isPrecise, isTrue);
    });

    test('accuracy 0 yields a full-axis blurry band', () {
      final a = resolveSiteDimensionDisplay(
        dimension: SiteDimensionKey.fossil,
        trueValue: 0.5,
        accuracy: 0.0,
        siteId: 1,
      );
      expect(a.blurSigma, kSiteDimensionMaxBlurSigma);
      expect(a.effectiveAccuracy, 0.0);
      expect(a.rangeStart, 0.0);
      expect(a.rangeEnd, 1.0);
      expect(a.rangeWidth, 1.0);
    });

    test('mid accuracy yields different seeded ranges per site', () {
      final a = resolveSiteDimensionDisplay(
        dimension: SiteDimensionKey.fossil,
        trueValue: 0.5,
        accuracy: 0.4,
        siteId: 1,
      );
      final b = resolveSiteDimensionDisplay(
        dimension: SiteDimensionKey.fossil,
        trueValue: 0.5,
        accuracy: 0.4,
        siteId: 2,
      );
      expect(a.rangeWidth, greaterThan(0.0));
      expect(a.rangeWidth, lessThan(1.0));
      expect(
        a.rangeStart == b.rangeStart && a.rangeEnd == b.rangeEnd,
        isFalse,
      );
    });

    test('same site + dimension is stable across calls', () {
      final a = resolveSiteDimensionDisplay(
        dimension: SiteDimensionKey.quality,
        trueValue: 0.33,
        accuracy: 0.25,
        siteId: 99,
      );
      final b = resolveSiteDimensionDisplay(
        dimension: SiteDimensionKey.quality,
        trueValue: 0.33,
        accuracy: 0.25,
        siteId: 99,
      );
      expect(a.rangeStart, b.rangeStart);
      expect(a.rangeEnd, b.rangeEnd);
      expect(a.blurSigma, b.blurSigma);
    });

    test('higher accuracy narrows the band and reduces blur', () {
      final low = resolveSiteDimensionDisplay(
        dimension: SiteDimensionKey.completeness,
        trueValue: 0.5,
        accuracy: 0.2,
        siteId: 11,
      );
      final high = resolveSiteDimensionDisplay(
        dimension: SiteDimensionKey.completeness,
        trueValue: 0.5,
        accuracy: 0.8,
        siteId: 11,
      );
      expect(high.rangeWidth, lessThan(low.rangeWidth));
      expect(high.blurSigma, lessThan(low.blurSigma));
    });

    test('depth 0 is always precise regardless of depth accuracy', () {
      final result = resolveSiteDimensionDisplay(
        dimension: SiteDimensionKey.depth,
        trueValue: 0.0,
        accuracy: 0.0,
        siteId: 7,
      );
      expect(result.rangeStart, 0.0);
      expect(result.rangeEnd, 0.0);
      expect(result.blurSigma, 0.0);
      expect(result.effectiveAccuracy, 1.0);
      expect(result.isPrecise, isTrue);
    });

    test('non-zero depth respects accuracy', () {
      final precise = resolveSiteDimensionDisplay(
        dimension: SiteDimensionKey.depth,
        trueValue: 0.78,
        accuracy: 1.0,
        siteId: 7,
      );
      final blurry = resolveSiteDimensionDisplay(
        dimension: SiteDimensionKey.depth,
        trueValue: 0.78,
        accuracy: 0.0,
        siteId: 7,
      );
      expect(precise.isPrecise, isTrue);
      expect(precise.rangeStart, closeTo(0.78, 1e-9));
      expect(blurry.blurSigma, kSiteDimensionMaxBlurSigma);
      expect(blurry.rangeWidth, greaterThan(0.7));
    });

    test('keeps trueValue even when the blurry band is jittered', () {
      final result = resolveSiteDimensionDisplay(
        dimension: SiteDimensionKey.quality,
        trueValue: 0.33,
        accuracy: 0.25,
        siteId: 99,
      );
      expect(result.trueValue, closeTo(0.33, 1e-9));
      expect(result.isPrecise, isFalse);
    });
  });

  group('applyExplorationAccuracyBoost', () {
    test('adds 1% per meter and caps at 1.0', () {
      expect(applyExplorationAccuracyBoost(0.01, 0), closeTo(0.01, 1e-9));
      expect(applyExplorationAccuracyBoost(0.01, 10), closeTo(0.11, 1e-9));
      expect(applyExplorationAccuracyBoost(0.5, 100), 1.0);
      expect(applyExplorationAccuracyBoost(0.99, 5), 1.0);
    });
  });

  group('applyDimensionAccuracyNoise', () {
    test('is stable per site/axis and varies across axes', () {
      const base = 0.50;
      final a = applyDimensionAccuracyNoise(
        baseAccuracy: base,
        siteId: 42,
        dimension: SiteDimensionKey.dino,
      );
      final b = applyDimensionAccuracyNoise(
        baseAccuracy: base,
        siteId: 42,
        dimension: SiteDimensionKey.dino,
      );
      final c = applyDimensionAccuracyNoise(
        baseAccuracy: base,
        siteId: 42,
        dimension: SiteDimensionKey.fossil,
      );
      expect(a, b);
      expect(a, isNot(c));
      expect(a, inInclusiveRange(0.20, 0.80));
      expect(c, inInclusiveRange(0.20, 0.80));
      final low = applyDimensionAccuracyNoise(
        baseAccuracy: 0.10,
        siteId: 42,
        dimension: SiteDimensionKey.dino,
      );
      expect(low, inInclusiveRange(0.0, 0.40));
      expect((low - 0.10).abs(), lessThanOrEqualTo(0.30 + 1e-9));
    });
  });
}
