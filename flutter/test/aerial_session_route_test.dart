import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesozoica/models/tool_session.dart';
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

  group('RouteGeometry.prefixUpToFraction / suffixFromFraction', () {
    test('prefix at 0 is start; at 1 is full route', () {
      final route = [
        const LatLng(40.0, -100.0),
        const LatLng(40.1, -100.0),
        const LatLng(40.1, -99.9),
      ];
      expect(RouteGeometry.prefixUpToFraction(route, 0), [route.first]);
      expect(RouteGeometry.prefixUpToFraction(route, 1), route);
    });

    test('prefix and suffix meet at midpoint fraction', () {
      final route = [
        const LatLng(40.0, -100.0),
        const LatLng(40.1, -100.0),
      ];
      final prefix = RouteGeometry.prefixUpToFraction(route, 0.5);
      final suffix = RouteGeometry.suffixFromFraction(route, 0.5);
      expect(prefix.length, greaterThanOrEqualTo(2));
      expect(suffix.length, greaterThanOrEqualTo(2));
      expect(prefix.last.latitude, closeTo(suffix.first.latitude, 1e-9));
      expect(prefix.last.longitude, closeTo(suffix.first.longitude, 1e-9));
      expect(
        RouteGeometry.lengthKm(prefix) + RouteGeometry.lengthKm(suffix),
        closeTo(RouteGeometry.lengthKm(route), 0.02),
      );
    });
  });

  group('aerialSessionProgressFraction', () {
    ToolSession session({
      required String status,
      DateTime? started,
      int durationS = 100,
    }) {
      return ToolSession(
        sessionId: 1,
        toolId: 1,
        actionKey: 'aerial_recon',
        status: status,
        startedAt: DateTime.utc(2026, 1, 1),
        state: {
          'route': [
            {'lat': 40.0, 'lon': -100.0},
            {'lat': 40.1, 'lon': -100.0},
          ],
          'route_length_km': 11,
          'flight_duration_s': durationS,
          if (started != null) 'flight_started_at': started.toIso8601String(),
          if (started != null)
            'flight_ends_at':
                started.add(Duration(seconds: durationS)).toIso8601String(),
        },
      );
    }

    test('pending is at start', () {
      final m = session(status: 'pending');
      expect(aerialSessionProgressFraction(m), 0);
    });

    test('active uses elapsed / duration (same as discovery timing)', () {
      final started = DateTime.utc(2026, 1, 1, 12);
      final m = session(status: 'active', started: started, durationS: 100);
      final now = started.add(const Duration(seconds: 40));
      expect(aerialSessionProgressFraction(m, now: now), closeTo(0.4, 1e-9));
    });

    test('clamps at end of flight', () {
      final started = DateTime.utc(2026, 1, 1, 12);
      final m = session(status: 'active', started: started, durationS: 100);
      final now = started.add(const Duration(seconds: 200));
      expect(aerialSessionProgressFraction(m, now: now), 1.0);
    });

    test('naive UTC timestamps from API are not shifted by local offset', () {
      final json = <String, dynamic>{
        'session_id': 1,
        'tool_id': 1,
        'action_key': 'aerial_recon',
        'status': 'active',
        'started_at': '2026-01-01T11:00:00',
        'state': {
          'route': [
            {'lat': 40.0, 'lon': -100.0},
            {'lat': 40.1, 'lon': -100.0},
          ],
          'route_length_km': 11,
          'flight_duration_s': 3600,
          'flight_started_at': '2026-01-01T12:00:00',
          'flight_ends_at': '2026-01-01T13:00:00',
        },
      };
      final m = ToolSession.fromJson(json);
      expect(m.flightStartedAt!.isUtc, isTrue);
      expect(m.flightStartedAt, DateTime.utc(2026, 1, 1, 12));
      final now = DateTime.utc(2026, 1, 1, 12, 30);
      expect(aerialSessionProgressFraction(m, now: now), closeTo(0.5, 1e-9));
    });
  });
}
