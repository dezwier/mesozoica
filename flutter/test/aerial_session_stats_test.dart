import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesozoica/models/tool_session.dart';

void main() {
  test('ToolSession parses aerial params/state and site count', () {
    final session = ToolSession.fromJson({
      'session_id': 5,
      'tool_id': 3,
      'action_key': 'aerial_scout',
      'status': 'active',
      'started_at': '2026-07-01T12:00:00',
      'params': {
        'flight_speed_kmh': 50,
        'max_route_km': 100,
        'discovery_chance': 0.02,
        'discovery_distance_m': 200,
      },
      'state': {
        'route': [
          {'lat': 40.0, 'lon': -100.0},
          {'lat': 40.1, 'lon': -100.0},
        ],
        'route_length_km': 12.5,
        'flight_duration_s': 900,
      },
      'events_summary': {
        'discovered_site_ids': [1, 2, 3],
        'discovered_count': 3,
      },
    });
    expect(session.actionKey, 'aerial_scout');
    expect(session.flightSpeedKmh, 50);
    expect(session.maxRouteKm, 100);
    expect(session.discoveryChance, 0.02);
    expect(session.discoveryDistanceM, 200);
    expect(session.discoveredSiteCount, 3);
    expect(session.route, hasLength(2));
    expect(session.route.first, const LatLng(40.0, -100.0));
  });
}
