import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesozoica/controllers/aerial_recon_controller.dart';
import 'package:mesozoica/services/tool_service.dart';

void main() {
  AerialReconMission mission({
    required int id,
    required String status,
  }) {
    return AerialReconMission(
      missionId: id,
      status: status,
      route: const [LatLng(40, -100), LatLng(40.1, -100)],
      routeLengthKm: 11,
      flightDurationS: 800,
      flightStartedAt: status == 'flying' ? DateTime.utc(2026, 1, 1) : null,
      flightEndsAt: status == 'done' ? DateTime.utc(2026, 1, 1, 1) : null,
      createdAt: DateTime.utc(2026, 1, 1),
      toolId: 1,
    );
  }

  test('focusMission sets focused and pending; take clears pending once', () {
    final controller = AerialReconController();
    final flying = mission(id: 3, status: 'flying');

    controller.focusMission(flying);
    expect(controller.focusedMission?.missionId, 3);
    expect(controller.pendingFocusMission?.missionId, 3);

    final taken = controller.takePendingFocusMission();
    expect(taken?.missionId, 3);
    expect(controller.pendingFocusMission, isNull);
    expect(controller.focusedMission?.missionId, 3);

    expect(controller.takePendingFocusMission(), isNull);

    controller.clearFocus();
    expect(controller.focusedMission, isNull);
  });

  test('missions filter into ongoing vs past', () {
    final items = [
      mission(id: 1, status: 'ensuring'),
      mission(id: 2, status: 'flying'),
      mission(id: 3, status: 'done'),
      mission(id: 4, status: 'failed'),
      mission(id: 5, status: 'cancelled'),
    ];
    final ongoing = items.where((m) => m.isActive).toList();
    final past = items.where((m) => m.isPast).toList();
    expect(ongoing.map((m) => m.missionId), [1, 2]);
    expect(past.map((m) => m.missionId), [3, 4, 5]);
  });
}
