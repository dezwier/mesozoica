import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/widgets/cards/site_dimension_display.dart';

void main() {
  group('resolveSiteDimensionDisplay', () {
    test('accuracy 1 is exact with no blur', () {
      final result = resolveSiteDimensionDisplay(
        dimension: SiteDimensionKey.dino,
        trueValue: 0.42,
        accuracy: 1.0,
        siteId: 50001,
      );
      expect(result.displayValue, closeTo(0.42, 1e-9));
      expect(result.blurSigma, 0.0);
      expect(result.effectiveAccuracy, 1.0);
    });

    test('accuracy 0 applies near-full-axis jitter and max blur', () {
      final a = resolveSiteDimensionDisplay(
        dimension: SiteDimensionKey.fossil,
        trueValue: 0.5,
        accuracy: 0.0,
        siteId: 1,
      );
      final b = resolveSiteDimensionDisplay(
        dimension: SiteDimensionKey.fossil,
        trueValue: 0.5,
        accuracy: 0.0,
        siteId: 2,
      );
      expect(a.blurSigma, kSiteDimensionMaxBlurSigma);
      expect(a.effectiveAccuracy, 0.0);
      expect(a.displayValue, inInclusiveRange(0.0, 1.0));
      // Different sites should generally diverge (seeded).
      expect(a.displayValue == b.displayValue, isFalse);
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
      expect(a.displayValue, b.displayValue);
      expect(a.blurSigma, b.blurSigma);
    });

    test('depth 0 is always precise regardless of depth accuracy', () {
      final result = resolveSiteDimensionDisplay(
        dimension: SiteDimensionKey.depth,
        trueValue: 0.0,
        accuracy: 0.0,
        siteId: 7,
      );
      expect(result.displayValue, 0.0);
      expect(result.blurSigma, 0.0);
      expect(result.effectiveAccuracy, 1.0);
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
      expect(precise.displayValue, closeTo(0.78, 1e-9));
      expect(blurry.blurSigma, kSiteDimensionMaxBlurSigma);
      expect(blurry.displayValue == precise.displayValue, isFalse);
    });
  });
}
