import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/services/location_service.dart';

void main() {
  group('shouldTrackLocation', () {
    test('tracks GPS while app is resumed and location is wanted', () {
      expect(
        shouldTrackLocation(
          wantsLocation: true,
          appForeground: true,
          backgroundExploring: false,
        ),
        isTrue,
      );
    });

    test('stops GPS when app is backgrounded without exploring', () {
      expect(
        shouldTrackLocation(
          wantsLocation: true,
          appForeground: false,
          backgroundExploring: false,
        ),
        isFalse,
      );
    });

    test('keeps GPS when backgrounded with exploring enabled', () {
      expect(
        shouldTrackLocation(
          wantsLocation: true,
          appForeground: false,
          backgroundExploring: true,
        ),
        isTrue,
      );
    });

    test('never tracks GPS without map or field session', () {
      expect(
        shouldTrackLocation(
          wantsLocation: false,
          appForeground: true,
          backgroundExploring: true,
        ),
        isFalse,
      );
    });
  });

  group('resolveGpsProfile', () {
    test('uses high precision on map tab in foreground', () {
      expect(
        resolveGpsProfile(
          mapForeground: true,
          appForeground: true,
          backgroundExploring: false,
          stationary: false,
        ),
        GpsProfile.high,
      );
    });

    test('uses field foreground when app open off map', () {
      expect(
        resolveGpsProfile(
          mapForeground: false,
          appForeground: true,
          backgroundExploring: true,
          stationary: false,
        ),
        GpsProfile.fieldForeground,
      );
    });

    test('uses field background when exploring while moving', () {
      expect(
        resolveGpsProfile(
          mapForeground: false,
          appForeground: false,
          backgroundExploring: true,
          stationary: false,
        ),
        GpsProfile.fieldBackground,
      );
    });

    test('uses idle background when exploring while stationary', () {
      expect(
        resolveGpsProfile(
          mapForeground: false,
          appForeground: false,
          backgroundExploring: true,
          stationary: true,
        ),
        GpsProfile.idleBackground,
      );
    });
  });
}
