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
  });
}
