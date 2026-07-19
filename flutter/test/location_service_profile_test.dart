import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/services/location_service.dart';

void main() {
  test('uses foreground GPS while map is open and app is resumed', () {
    expect(
      shouldUseBackgroundLocationProfile(
        backgroundPreferred: true,
        mapForeground: true,
        appForeground: true,
      ),
      isFalse,
    );
  });

  test('uses background GPS when app is backgrounded even if map tab active',
      () {
    expect(
      shouldUseBackgroundLocationProfile(
        backgroundPreferred: true,
        mapForeground: true,
        appForeground: false,
      ),
      isTrue,
    );
  });

  test('uses background GPS when map is not foreground', () {
    expect(
      shouldUseBackgroundLocationProfile(
        backgroundPreferred: true,
        mapForeground: false,
        appForeground: true,
      ),
      isTrue,
    );
  });

  test('never uses background GPS without field-session preference', () {
    expect(
      shouldUseBackgroundLocationProfile(
        backgroundPreferred: false,
        mapForeground: false,
        appForeground: false,
      ),
      isFalse,
    );
  });
}
