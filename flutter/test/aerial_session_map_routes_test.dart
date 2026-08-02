import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/site_map_filters.dart';
import 'package:mesozoica/models/tool_session.dart';
import 'package:mesozoica/widgets/map/mapbox_aerial_annotations.dart';

void main() {
  ToolSession session({
    required int id,
    required String status,
    required DateTime startedAt,
    DateTime? flightEndsAt,
  }) {
    return ToolSession(
      sessionId: id,
      toolId: 1,
      actionKey: 'aerial_recon',
      status: status,
      startedAt: startedAt,
      state: {
        'route': [
          {'lat': 40.0, 'lon': -100.0},
          {'lat': 40.1, 'lon': -100.0},
        ],
        'route_length_km': 11,
        'flight_duration_s': 100,
        'flight_started_at': startedAt.toIso8601String(),
        'flight_ends_at':
            (flightEndsAt ?? startedAt.add(const Duration(hours: 1)))
                .toIso8601String(),
      },
    );
  }

  test('always includes active sessions', () {
    final now = DateTime.utc(2026, 7, 23, 12);
    final flying = session(
      id: 1,
      status: 'active',
      startedAt: now.subtract(const Duration(days: 2)),
    );
    final visible = aerialSessionsForMap(
      sessions: [flying],
      showPastAerialRoutes: false,
      now: now,
    );
    expect(visible.map((m) => m.sessionId), [1]);
  });

  test('hides past sessions when disabled', () {
    final now = DateTime.utc(2026, 7, 23, 12);
    final past = session(
      id: 2,
      status: 'completed',
      startedAt: now.subtract(const Duration(hours: 2)),
      flightEndsAt: now.subtract(const Duration(hours: 1)),
    );
    final visible = aerialSessionsForMap(
      sessions: [past],
      showPastAerialRoutes: false,
      now: now,
    );
    expect(visible, isEmpty);
  });

  test('shows past sessions within 24h when enabled', () {
    final now = DateTime.utc(2026, 7, 23, 12);
    final recent = session(
      id: 3,
      status: 'completed',
      startedAt: now.subtract(const Duration(hours: 5)),
      flightEndsAt: now.subtract(const Duration(hours: 4)),
    );
    final old = session(
      id: 4,
      status: 'completed',
      startedAt: now.subtract(const Duration(days: 3)),
      flightEndsAt: now.subtract(const Duration(days: 2)),
    );
    final visible = aerialSessionsForMap(
      sessions: [recent, old],
      showPastAerialRoutes: true,
      now: now,
    );
    expect(visible.map((m) => m.sessionId), [3]);
    expect(pastAerialRouteMaxAge, const Duration(hours: 24));
  });
}
