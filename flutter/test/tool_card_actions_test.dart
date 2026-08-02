import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/tool.dart';
import 'package:mesozoica/models/tool_session.dart';
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
    expect(find.text('15m 0s left'), findsOneWidget);
    expect(find.text('HISTORY'), findsOneWidget);
    expect(find.text('No history yet'), findsOneWidget);
    expect(find.text('Helicopter'), findsOneWidget);
    expect(find.textContaining('Site Discovery'), findsNothing);
    expect(find.text('Rarity'), findsNothing);
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(5));

    await tester.tap(find.text('Deploy'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('ToolCardBack shows scientific subtitle and filled rarity stars',
      (tester) async {
    final owned = ToolSummary(
      id: 10,
      toolTypeId: 1,
      name: 'Aerial Recon',
      category: '1 site_discovery',
      scientificTool: 'helicopter',
      description: 'Scout loop',
      rarity: 3,
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

    expect(find.text('Helicopter'), findsOneWidget);
    expect(find.textContaining('Site Discovery'), findsNothing);
    expect(find.textContaining('Obtained'), findsNothing);
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(3));
    expect(find.byIcon(Icons.star_border), findsNothing);
    expect(find.text('Rarity'), findsNothing);
  });

  testWidgets('ToolCardBack lists compact history', (tester) async {
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
    final started =
        DateTime.now().toUtc().subtract(const Duration(hours: 2));
    final obtained =
        DateTime.now().toUtc().subtract(const Duration(days: 3));
    final history = [
      ToolHistoryEntry(
        kind: 'session',
        at: started,
        session: ToolSession(
          sessionId: 9,
          toolId: 1,
          actionKey: 'aerial_recon',
          status: 'completed',
          startedAt: started,
          endedAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
          usedDurationS: 2700,
          stopReason: 'exhausted',
          params: const {'flight_speed_kmh': 50},
          state: const {'route_length_km': 12.5},
          eventsSummary: const ToolSessionEventsSummary(
            discoveredSiteIds: [1, 2],
            discoveredCount: 2,
          ),
        ),
      ),
      ToolHistoryEntry(
        kind: 'role',
        at: obtained,
        roleAction: 'owned',
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
                history: history,
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
    expect(find.text('Obtained'), findsOneWidget);
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

  testWidgets('ToolCardBack shows In use and disables action when inUse',
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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ToolCardBack(
                tool: owned,
                onAction: () {},
                inUse: true,
                remainingDurationS: 900,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('In use'), findsOneWidget);
    expect(find.text('Deploy'), findsNothing);
    final action = tester.widget<ChromeActionButton>(
      find.widgetWithText(ChromeActionButton, 'In use'),
    );
    expect(action.onPressed, isNull);
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
    expect(find.text('0s left'), findsOneWidget);
  });
}
