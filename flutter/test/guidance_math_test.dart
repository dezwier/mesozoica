import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/utils/guidance_math.dart';

void main() {
  group('GuidanceMath.distanceStepM', () {
    test('hits ladder anchors', () {
      expect(GuidanceMath.distanceStepM(0.0), 200);
      expect(GuidanceMath.distanceStepM(0.25), 100);
      expect(GuidanceMath.distanceStepM(0.5), 50);
      expect(GuidanceMath.distanceStepM(0.75), 25);
      expect(GuidanceMath.distanceStepM(1.0), 1);
    });

    test('interpolates between ladder keys', () {
      expect(GuidanceMath.distanceStepM(0.125), 150);
      expect(GuidanceMath.distanceStepM(0.375), 75);
    });
  });

  group('GuidanceMath.formatDistance', () {
    test('exactness 0 uses 200 m bands', () {
      expect(
        GuidanceMath.formatDistance(distanceM: 50, exactness: 0),
        '0–200 m',
      );
      expect(
        GuidanceMath.formatDistance(distanceM: 250, exactness: 0),
        '200–400 m',
      );
    });

    test('exactness 0.25 uses 100 m bands', () {
      expect(
        GuidanceMath.formatDistance(distanceM: 137, exactness: 0.25),
        '100–200 m',
      );
    });

    test('exactness 0.5 uses 50 m bands', () {
      expect(
        GuidanceMath.formatDistance(distanceM: 437, exactness: 0.5),
        '400–450 m',
      );
    });

    test('exactness 0.75 uses 25 m bands', () {
      expect(
        GuidanceMath.formatDistance(distanceM: 112, exactness: 0.75),
        '100–125 m',
      );
    });

    test('exactness 1 shows precise meters', () {
      expect(
        GuidanceMath.formatDistance(distanceM: 437, exactness: 1),
        '437 m',
      );
    });

    test('km bands when both edges are >= 1000', () {
      expect(
        GuidanceMath.formatDistance(distanceM: 1100, exactness: 0),
        '1–1.2 km',
      );
    });
  });

  group('GuidanceMath.directionRangeWidthDeg', () {
    test('180 at exactness 0 and min at exactness 1', () {
      expect(GuidanceMath.directionRangeWidthDeg(exactness: 0, minDeg: 4), 180);
      expect(GuidanceMath.directionRangeWidthDeg(exactness: 1, minDeg: 4), 4);
      expect(
        GuidanceMath.directionRangeWidthDeg(exactness: 0.5, minDeg: 4),
        92,
      );
    });
  });

  group('GuidanceMath.sampleRangeCenterOffsetDeg', () {
    test('samples stay within half-width', () {
      final rng = math.Random(42);
      for (var i = 0; i < 40; i++) {
        final sample = GuidanceMath.sampleRangeCenterOffsetDeg(
          halfWidthDeg: 90,
          random: rng,
        );
        expect(sample, inInclusiveRange(-90, 90));
      }
      expect(
        GuidanceMath.sampleRangeCenterOffsetDeg(halfWidthDeg: 0, random: rng),
        0,
      );
    });
  });

  group('GuidanceMath.rangeCenterScreenDeg', () {
    test('relative to device heading', () {
      expect(
        GuidanceMath.rangeCenterScreenDeg(
          trueBearingDeg: 90,
          deviceHeadingDeg: 0,
          centerOffsetDeg: 0,
        ),
        90,
      );
      expect(
        GuidanceMath.rangeCenterScreenDeg(
          trueBearingDeg: 90,
          deviceHeadingDeg: 90,
          centerOffsetDeg: 0,
        ),
        0,
      );
      expect(
        GuidanceMath.rangeCenterScreenDeg(
          trueBearingDeg: 90,
          deviceHeadingDeg: 0,
          centerOffsetDeg: 10,
        ),
        100,
      );
    });
  });
}
