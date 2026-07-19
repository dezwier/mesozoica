import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/services/location_service.dart';

void main() {
  test('uses foreground GPS while app is resumed on any tab', () {
    expect(
      shouldUseBackgroundLocationProfile(
        backgroundPreferred: true,
        appForeground: true,
      ),
      isFalse,
    );
  });

  test('uses background GPS when app is backgrounded or locked', () {
    expect(
      shouldUseBackgroundLocationProfile(
        backgroundPreferred: true,
        appForeground: false,
      ),
      isTrue,
    );
  });

  test('never uses background GPS without field-session preference', () {
    expect(
      shouldUseBackgroundLocationProfile(
        backgroundPreferred: false,
        appForeground: false,
      ),
      isFalse,
    );
  });
}
