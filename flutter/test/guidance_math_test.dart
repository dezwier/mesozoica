import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/utils/guidance_math.dart';

void main() {
  group('GuidanceMath.formatDistance', () {
    test('low exactness uses 5 band labels', () {
      expect(
        GuidanceMath.formatDistance(distanceM: 100, exactness: 0),
        'Very close',
      );
      expect(
        GuidanceMath.formatDistance(distanceM: 300, exactness: 0.2),
        'Quite close',
      );
      expect(
        GuidanceMath.formatDistance(distanceM: 600, exactness: 0.32),
        'Somewhat far',
      );
      expect(
        GuidanceMath.formatDistance(distanceM: 1200, exactness: 0),
        'Very far',
      );
    });

    test('mid exactness rounds to 100 m', () {
      expect(
        GuidanceMath.formatDistance(distanceM: 437, exactness: 0.5),
        '~400 m',
      );
      expect(
        GuidanceMath.formatDistance(distanceM: 460, exactness: 0.5),
        '~500 m',
      );
    });

    test('high exactness shows precise meters', () {
      expect(
        GuidanceMath.formatDistance(distanceM: 437, exactness: 0.9),
        '437 m',
      );
    });
  });

  group('GuidanceMath.jitter', () {
    test('amplitude is max at exactness 0 and zero at 1', () {
      expect(
        GuidanceMath.jitterAmplitudeDeg(exactness: 0, maxJitterDeg: 90),
        90,
      );
      expect(
        GuidanceMath.jitterAmplitudeDeg(exactness: 1, maxJitterDeg: 90),
        0,
      );
      expect(
        GuidanceMath.jitterAmplitudeDeg(exactness: 0.5, maxJitterDeg: 90),
        45,
      );
    });

    test('sample stays within amplitude', () {
      final rng = math.Random(42);
      for (var i = 0; i < 40; i++) {
        final sample = GuidanceMath.sampleJitterDeg(
          amplitudeDeg: 90,
          random: rng,
        );
        expect(sample, inInclusiveRange(-90, 90));
      }
      expect(
        GuidanceMath.sampleJitterDeg(amplitudeDeg: 0, random: rng),
        0,
      );
    });
  });

  group('GuidanceMath.needleScreenDeg', () {
    test('relative to device heading', () {
      expect(
        GuidanceMath.needleScreenDeg(
          trueBearingDeg: 90,
          deviceHeadingDeg: 0,
          jitterDeg: 0,
        ),
        90,
      );
      expect(
        GuidanceMath.needleScreenDeg(
          trueBearingDeg: 90,
          deviceHeadingDeg: 90,
          jitterDeg: 0,
        ),
        0,
      );
    });
  });
}
