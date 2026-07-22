import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/services/location_service.dart';

void main() {
  test('tracks GPS while app is resumed and location is wanted', () {
    expect(
      shouldTrackLocation(
        wantsLocation: true,
        appForeground: true,
      ),
      isTrue,
    );
  });

  test('stops GPS when app is backgrounded or locked', () {
    expect(
      shouldTrackLocation(
        wantsLocation: true,
        appForeground: false,
      ),
      isFalse,
    );
  });

  test('never tracks GPS without map or field session', () {
    expect(
      shouldTrackLocation(
        wantsLocation: false,
        appForeground: true,
      ),
      isFalse,
    );
  });
}
