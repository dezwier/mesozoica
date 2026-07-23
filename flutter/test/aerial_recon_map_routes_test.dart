import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesozoica/models/site_map_filters.dart';
import 'package:mesozoica/services/tool_service.dart';
import 'package:mesozoica/widgets/map/mapbox_aerial_recon_annotations.dart';

void main() {
  AerialReconMission mission({
    required int id,
    required String status,
    required DateTime createdAt,
    DateTime? flightEndsAt,
  }) {
    return AerialReconMission(
      missionId: id,
      status: status,
      route: const [LatLng(40, -100), LatLng(40.1, -100)],
      routeLengthKm: 11,
      flightDurationS: 100,
      flightStartedAt: createdAt,
      flightEndsAt: flightEndsAt ?? createdAt.add(const Duration(hours: 1)),
      createdAt: createdAt,
      toolId: 1,
    );
  }

  test('always includes active missions', () {
    final now = DateTime.utc(2026, 7, 23, 12);
    final flying = mission(
      id: 1,
      status: 'flying',
      createdAt: now.subtract(const Duration(days: 2)),
    );
    final visible = aerialReconMissionsForMap(
      missions: [flying],
      showPastReconRoutes: false,
      now: now,
    );
    expect(visible.map((m) => m.missionId), [1]);
  });

  test('hides past missions by default', () {
    final now = DateTime.utc(2026, 7, 23, 12);
    final past = mission(
      id: 2,
      status: 'done',
      createdAt: now.subtract(const Duration(hours: 2)),
      flightEndsAt: now.subtract(const Duration(hours: 1)),
    );
    final visible = aerialReconMissionsForMap(
      missions: [past],
      showPastReconRoutes: false,
      now: now,
    );
    expect(visible, isEmpty);
  });

  test('shows past missions within 24h when enabled', () {
    final now = DateTime.utc(2026, 7, 23, 12);
    final recent = mission(
      id: 3,
      status: 'done',
      createdAt: now.subtract(const Duration(hours: 5)),
      flightEndsAt: now.subtract(const Duration(hours: 4)),
    );
    final old = mission(
      id: 4,
      status: 'done',
      createdAt: now.subtract(const Duration(days: 3)),
      flightEndsAt: now.subtract(const Duration(days: 2)),
    );
    final visible = aerialReconMissionsForMap(
      missions: [recent, old],
      showPastReconRoutes: true,
      now: now,
    );
    expect(visible.map((m) => m.missionId), [3]);
    expect(pastReconRouteMaxAge, const Duration(hours: 24));
  });
}
