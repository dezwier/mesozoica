import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/tool.dart';
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

  testWidgets('ToolCardBack shows action verb and disabled Info by default', (tester) async {
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
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Deploy'), findsOneWidget);
    expect(find.text('Info'), findsOneWidget);
    expect(find.textContaining('Site Discovery'), findsOneWidget);

    await tester.tap(find.text('Deploy'));
    await tester.pump();
    expect(tapped, isTrue);

    final info = tester.widget<ChromeActionButton>(
      find.widgetWithText(ChromeActionButton, 'Info'),
    );
    expect(info.onPressed, isNull);
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

  testWidgets('ToolCardBack enables Info when onInfo is set', (tester) async {
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

    var infoTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ToolCardBack(
                tool: owned,
                onAction: () {},
                onInfo: () => infoTapped = true,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Info'));
    await tester.pump();
    expect(infoTapped, isTrue);
  });

  testWidgets('ToolCardBack disables action when not owned', (tester) async {
    const unowned = ToolSummary(
      id: 2,
      name: 'Formation Map',
      category: '1 site_discovery',
      scientificTool: 'geological map',
      description: 'Read formations',
      rarity: 1,
      action: 'Read',
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
      find.widgetWithText(ChromeActionButton, 'Read'),
    );
    expect(deploy.onPressed, isNull);
  });
}
