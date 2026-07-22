import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/services/gps_odometer.dart';

void main() {
  late GpsOdometer odometer;

  setUp(() {
    odometer = GpsOdometer();
  });

  GpsFix fix({
    required double lat,
    required double lon,
    required DateTime at,
    double accuracy = 10,
    double? speed,
  }) {
    return GpsFix(
      latitude: lat,
      longitude: lon,
      timestamp: at,
      accuracyMeters: accuracy,
      speedMps: speed,
    );
  }

  test('first fix credits nothing', () {
    final result = odometer.addFix(
      fix(lat: 51.0, lon: 4.0, at: DateTime(2026, 7, 22, 10)),
    );
    expect(result.acceptedMeters, 0);
    expect(result.accepted, isFalse);
  });

  test('accepts walking speed segment', () {
    final t0 = DateTime(2026, 7, 22, 10, 0, 0);
    odometer.addFix(fix(lat: 51.0, lon: 4.0, at: t0));
    // ~11 m north in 5 s ≈ 2.2 m/s (brisk walk)
    final result = odometer.addFix(
      fix(lat: 51.0001, lon: 4.0, at: t0.add(const Duration(seconds: 5))),
    );
    expect(result.accepted, isTrue);
    expect(result.acceptedMeters, greaterThan(8));
    expect(result.acceptedMeters, lessThan(15));
  });

  test('rejects car speed (~50 km/h)', () {
    final t0 = DateTime(2026, 7, 22, 10, 0, 0);
    odometer.addFix(fix(lat: 51.0, lon: 4.0, at: t0));
    // ~42 m in 3 s ≈ 14 m/s (~50 km/h) but also over max segment if too far;
    // use ~14 m in 1 s ≈ 14 m/s.
    final result = odometer.addFix(
      fix(
        lat: 51.000126,
        lon: 4.0,
        at: t0.add(const Duration(seconds: 1)),
      ),
    );
    expect(result.accepted, isFalse);
    expect(result.rejectReason, 'speed');
  });

  test('rejects bad accuracy', () {
    final t0 = DateTime(2026, 7, 22, 10, 0, 0);
    odometer.addFix(fix(lat: 51.0, lon: 4.0, at: t0));
    final result = odometer.addFix(
      fix(
        lat: 51.00005,
        lon: 4.0,
        at: t0.add(const Duration(seconds: 3)),
        accuracy: 80,
      ),
    );
    expect(result.accepted, isFalse);
    expect(result.rejectReason, 'accuracy');
  });

  test('rejects teleport jump', () {
    final t0 = DateTime(2026, 7, 22, 10, 0, 0);
    odometer.addFix(fix(lat: 51.0, lon: 4.0, at: t0));
    final result = odometer.addFix(
      fix(
        lat: 51.002,
        lon: 4.0,
        at: t0.add(const Duration(seconds: 5)),
      ),
    );
    expect(result.accepted, isFalse);
    expect(result.rejectReason, 'jump');
  });

  test('rejects platform-reported high speed', () {
    final t0 = DateTime(2026, 7, 22, 10, 0, 0);
    odometer.addFix(fix(lat: 51.0, lon: 4.0, at: t0));
    final result = odometer.addFix(
      fix(
        lat: 51.00005,
        lon: 4.0,
        at: t0.add(const Duration(seconds: 3)),
        speed: 15,
      ),
    );
    expect(result.accepted, isFalse);
    expect(result.rejectReason, 'platform_speed');
  });

  test('reset clears previous fix', () {
    final t0 = DateTime(2026, 7, 22, 10, 0, 0);
    odometer.addFix(fix(lat: 51.0, lon: 4.0, at: t0));
    odometer.reset();
    final result = odometer.addFix(
      fix(
        lat: 51.0001,
        lon: 4.0,
        at: t0.add(const Duration(seconds: 5)),
      ),
    );
    expect(result.accepted, isFalse);
    expect(result.acceptedMeters, 0);
  });
}
