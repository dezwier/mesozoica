import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/tool.dart';
import 'package:mesozoica/models/tool_use.dart';
import 'package:mesozoica/widgets/cards/tool_card_back.dart';
import 'package:mesozoica/widgets/common/chrome_action_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('isToolInstance is true when occurrence id equals tool type id', () {
    final scout = ToolSummary(
      id: 1,
      toolTypeId: 1,
      name: 'Aerial Scout',
      category: '1 site_discovery',
      scientificTool: 'drone',
      description: 'Maps outcrops',
      rarity: 2,
      level: 1,
      spawnDate: DateTime.utc(2026, 7, 1),
    );
    expect(scout.isToolInstance, isTrue);
    expect(scout.displayOccurrenceNumber, '#1');
    expect(scout.occurrenceIdBadgeLabel, '#1');

    final withVersion = scout.copyWith(version: 'Summer 26');
    expect(withVersion.occurrenceIdBadgeLabel, '#1 · Summer 26');
  });

  test('isToolInstance is false for catalog rows without spawnDate', () {
    const catalog = ToolSummary(
      id: 1,
      toolTypeId: 1,
      name: 'Aerial Scout',
      category: '1 site_discovery',
      scientificTool: 'drone',
      description: 'Maps outcrops',
      rarity: 2,
    );
    expect(catalog.isToolInstance, isFalse);
  });

  testWidgets('ToolCardBack shows centered action and remaining, no Info',
      (tester) async {
    const owned = ToolSummary(
      id: 1,
      name: 'Aerial Recon',
      category: '1 site_discovery',
      scientificTool: 'helicopter',
      description: 'Scout loop',
      rarity: 5,
      action: 'Deploy',
      level: 1,
      remainingDurationS: 900,
    );

    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ToolCardBack(
                tool: owned,
                onAction: () => tapped = true,
                remainingDurationS: 900,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Deploy'), findsOneWidget);
    expect(find.text('Info'), findsNothing);
    expect(find.text('15m left'), findsOneWidget);
    expect(find.text('USES'), findsOneWidget);
    expect(find.textContaining('Site Discovery'), findsOneWidget);

    await tester.tap(find.text('Deploy'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('ToolCardBack shows Obtained subtitle when spawnDate is set',
      (tester) async {
    final owned = ToolSummary(
      id: 10,
      toolTypeId: 1,
      name: 'Aerial Recon',
      category: '1 site_discovery',
      scientificTool: 'helicopter',
      description: 'Scout loop',
      rarity: 5,
      action: 'Deploy',
      level: 1,
      version: 'Original',
      spawnDate: DateTime.now().toUtc().subtract(const Duration(minutes: 45)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ToolCardBack(
                tool: owned,
                onAction: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('Site Discovery - Helicopter - Obtained 45m ago'),
      findsOneWidget,
    );
    expect(find.text('#10 · Original'), findsNothing);
    expect(find.text('#10'), findsNothing);
  });

  testWidgets('ToolCardBack lists compact uses', (tester) async {
    const owned = ToolSummary(
      id: 1,
      name: 'Aerial Recon',
      category: '1 site_discovery',
      scientificTool: 'helicopter',
      description: 'Scout loop',
      rarity: 5,
      action: 'Deploy',
      level: 1,
    );
    final uses = [
      ToolUse(
        id: 9,
        kind: 'aerial_mission',
        actionKey: 'aerial_recon',
        status: 'done',
        startedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
        endedAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
        durationS: 2700,
        stopReason: 'exhausted',
        params: const {'route_length_km': 12.5, 'flight_speed_kmh': 50},
        result: const {'discovered_count': 2},
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 480,
              child: ToolCardBack(
                tool: owned,
                onAction: () {},
                uses: uses,
                remainingDurationS: 900,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('done'), findsOneWidget);
    expect(find.text('45m'), findsOneWidget);
    expect(find.textContaining('2 sites'), findsOneWidget);
  });

  testWidgets('ToolCardBack disables action when not owned', (tester) async {
    const unowned = ToolSummary(
      id: 2,
      name: 'Orbit Survey',
      category: '1 site_discovery',
      scientificTool: 'satellite imagery',
      description: 'Read formations',
      rarity: 1,
      action: 'Scan',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ToolCardBack(tool: unowned, onAction: () {}),
            ),
          ),
        ),
      ),
    );

    final deploy = tester.widget<ChromeActionButton>(
      find.widgetWithText(ChromeActionButton, 'Scan'),
    );
    expect(deploy.onPressed, isNull);
  });

  testWidgets('ToolCardBack disables action when remaining is zero',
      (tester) async {
    const owned = ToolSummary(
      id: 1,
      name: 'Geo Compass',
      category: '1 site_discovery',
      scientificTool: 'compass',
      description: 'Point',
      rarity: 1,
      action: 'Consult',
      level: 1,
      remainingDurationS: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ToolCardBack(
                tool: owned,
                onAction: () {},
                remainingDurationS: 0,
              ),
            ),
          ),
        ),
      ),
    );

    final action = tester.widget<ChromeActionButton>(
      find.widgetWithText(ChromeActionButton, 'Consult'),
    );
    expect(action.onPressed, isNull);
    expect(find.text('0m left'), findsOneWidget);
  });
}
