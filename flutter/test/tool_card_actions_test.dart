import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/tool.dart';
import 'package:mesozoica/widgets/cards/tool_card_back.dart';
import 'package:mesozoica/widgets/common/chrome_action_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
                showInstanceId: true,
                onAction: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('ID 10 - Site Discovery - Helicopter - Obtained 45m ago'),
      findsOneWidget,
    );
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
