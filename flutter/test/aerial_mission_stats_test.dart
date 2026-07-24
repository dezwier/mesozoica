import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesozoica/services/tool_service.dart';

void main() {
  test('AerialMission parses flight params and site count', () {
    final mission = AerialMission.fromJson({
      'mission_id': 5,
      'action_key': 'aerial_scout',
      'status': 'flying',
      'route': [
        {'lat': 40.0, 'lon': -100.0},
        {'lat': 40.1, 'lon': -100.0},
      ],
      'route_length_km': 12.5,
      'flight_duration_s': 900,
      'flight_speed_kmh': 50,
      'max_route_km': 100,
      'discovery_chance': 0.02,
      'discovery_distance_m': 200,
      'created_at': '2026-07-01T12:00:00',
      'tool_id': 3,
      'discovered_site_ids': [1, 2, 3],
    });
    expect(mission.actionKey, 'aerial_scout');
    expect(mission.flightSpeedKmh, 50);
    expect(mission.maxRouteKm, 100);
    expect(mission.discoveryChance, 0.02);
    expect(mission.discoveryDistanceM, 200);
    expect(mission.discoveredSiteCount, 3);
    expect(mission.route, hasLength(2));
    expect(mission.route.first, const LatLng(40.0, -100.0));
  });
}
