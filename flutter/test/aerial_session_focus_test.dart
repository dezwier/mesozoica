import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/config/game_config.dart';
import 'package:mesozoica/controllers/aerial_session_controller.dart';
import 'package:mesozoica/models/tool.dart';
import 'package:mesozoica/models/tool_session.dart';

import 'helpers/game_config_test_helpers.dart';

void main() {
  tearDown(() {
    GameConfig.debugReset();
  });

  ToolSession session({required int id, required String status}) {
    return ToolSession(
      sessionId: id,
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
        'flight_duration_s': 800,
        if (status == 'active') 'flight_started_at': '2026-01-01T00:00:00',
        if (status == 'completed') 'flight_ends_at': '2026-01-01T01:00:00',
      },
    );
  }

  test('focusSession sets focused and pending; take clears pending once', () {
    final controller = AerialSessionController();
    final flying = session(id: 3, status: 'active');

    controller.focusSession(flying);
    expect(controller.focusedSession?.sessionId, 3);
    expect(controller.pendingFocusSession?.sessionId, 3);

    final taken = controller.takePendingFocusSession();
    expect(taken?.sessionId, 3);
    expect(controller.pendingFocusSession, isNull);
    expect(controller.focusedSession?.sessionId, 3);

    expect(controller.takePendingFocusSession(), isNull);

    controller.clearFocus();
    expect(controller.focusedSession, isNull);
  });

  test('beginDraw queues draw-camera fit; cancel clears it', () async {
    GameConfig.debugSetInstance(await loadGameConfigForTest());
    final controller = AerialSessionController();
    const tool = ToolSummary(
      id: 1,
      name: 'Aerial Scout',
      category: '1 site_discovery',
      scientificTool: 'drone',
      description: 'Scout loop',
      rarity: 3,
      action: 'Launch',
      level: 1,
    );

    expect(controller.pendingDrawCamera, isFalse);
    controller.beginDraw(tool);
    expect(controller.isDrawMode, isTrue);
    expect(controller.pendingDrawCamera, isTrue);

    expect(controller.takePendingDrawCamera(), isTrue);
    expect(controller.pendingDrawCamera, isFalse);
    expect(controller.takePendingDrawCamera(), isFalse);

    controller.beginDraw(tool);
    expect(controller.pendingDrawCamera, isTrue);
    controller.cancelDraw();
    expect(controller.pendingDrawCamera, isFalse);
    expect(controller.takePendingDrawCamera(), isFalse);
  });

  test('sessions filter into ongoing vs past', () {
    final items = [
      session(id: 1, status: 'pending'),
      session(id: 2, status: 'active'),
      session(id: 3, status: 'completed'),
      session(id: 4, status: 'failed'),
      session(id: 5, status: 'cancelled'),
    ];
    final ongoing = items.where((m) => m.isActive).toList();
    final past = items.where((m) => m.isPast).toList();
    expect(ongoing.map((m) => m.sessionId), [1, 2]);
    expect(past.map((m) => m.sessionId), [3, 4, 5]);
  });

  test('hudSession hides completed and arrived flights', () {
    final controller = AerialSessionController();
    final completed = session(id: 3, status: 'completed');
    controller.focusSession(completed);
    expect(controller.hudSession, isNull);

    final arrived = ToolSession(
      sessionId: 7,
      toolId: 1,
      actionKey: 'aerial_recon',
      status: 'active',
      startedAt: DateTime.utc(2026, 1, 1),
      state: {
        'route': [
          {'lat': 40.0, 'lon': -100.0},
          {'lat': 40.1, 'lon': -100.0},
        ],
        'route_length_km': 11,
        'flight_duration_s': 60,
        'flight_started_at': '2026-01-01T00:00:00.000',
        'flight_ends_at': '2026-01-01T00:01:00.000',
      },
    );
    controller.focusSession(arrived);
    expect(controller.hudSession, isNull);
  });
}
