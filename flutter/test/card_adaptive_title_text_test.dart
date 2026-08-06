import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/widgets/cards/card_adaptive_title_text.dart';

void main() {
  testWidgets('CardAdaptiveTitleText keeps full size when title fits', (
    tester,
  ) async {
    const style = TextStyle(fontSize: 36);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: CardAdaptiveTitleText(text: 'T. rex', style: style),
            ),
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('T. rex'));
    expect(text.style?.fontSize, 36);
    expect(find.byType(FittedBox), findsOneWidget);
  });

  testWidgets('CardAdaptiveTitleText scales down long titles to one line', (
    tester,
  ) async {
    const style = TextStyle(fontSize: 36);
    const longName =
        'Supercalifragilisticexpialidocus maximus longissimus namus';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              child: CardAdaptiveTitleText(text: longName, style: style),
            ),
          ),
        ),
      ),
    );

    expect(find.text(longName), findsOneWidget);
    expect(find.byType(FittedBox), findsOneWidget);
  });
}
