import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:mesozoica/services/tool_service.dart';
import 'package:mesozoica/utils/route_geometry.dart';

void main() {
  group('RouteGeometry.pointAtFraction', () {
    test('returns endpoints at 0 and 1', () {
      final route = [
        const LatLng(40.0, -100.0),
        const LatLng(40.1, -100.0),
        const LatLng(40.1, -99.9),
      ];
      expect(RouteGeometry.pointAtFraction(route, 0).latitude, 40.0);
      expect(RouteGeometry.pointAtFraction(route, 1).longitude, closeTo(-99.9, 1e-9));
    });

    test('midpoint is roughly halfway along arc', () {
      final route = [
        const LatLng(40.0, -100.0),
        const LatLng(40.1, -100.0),
      ];
      final mid = RouteGeometry.pointAtFraction(route, 0.5);
      expect(mid.latitude, closeTo(40.05, 0.001));
      expect(mid.longitude, closeTo(-100.0, 1e-6));
    });
  });

  group('aerialReconProgressFraction', () {
    AerialReconMission mission({
      required String status,
      DateTime? started,
      int durationS = 100,
    }) {
      return AerialReconMission(
        missionId: 1,
        status: status,
        route: const [LatLng(40, -100), LatLng(40.1, -100)],
        routeLengthKm: 11,
        flightDurationS: durationS,
        flightStartedAt: started,
        flightEndsAt: started?.add(Duration(seconds: durationS)),
        createdAt: DateTime.utc(2026, 1, 1),
        toolId: 1,
      );
    }

    test('ensuring is at start', () {
      final m = mission(status: 'ensuring');
      expect(aerialReconProgressFraction(m), 0);
    });

    test('flying uses elapsed / duration (same as discovery timing)', () {
      final started = DateTime.utc(2026, 1, 1, 12);
      final m = mission(status: 'flying', started: started, durationS: 100);
      final now = started.add(const Duration(seconds: 40));
      expect(aerialReconProgressFraction(m, now: now), closeTo(0.4, 1e-9));
    });

    test('clamps at end of flight', () {
      final started = DateTime.utc(2026, 1, 1, 12);
      final m = mission(status: 'flying', started: started, durationS: 100);
      final now = started.add(const Duration(seconds: 200));
      expect(aerialReconProgressFraction(m, now: now), 1.0);
    });
  });
}
