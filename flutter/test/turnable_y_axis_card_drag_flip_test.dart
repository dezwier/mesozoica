import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/widgets/cards/turnable_y_axis_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget card({required bool enableDragFlip}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            child: TurnableYAxisCard(
              enableDragFlip: enableDragFlip,
              front: const ColoredBox(
                color: Colors.blue,
                child: SizedBox(
                  width: 200,
                  height: 280,
                  child: Center(child: Text('FRONT')),
                ),
              ),
              back: const ColoredBox(
                color: Colors.red,
                child: SizedBox(
                  width: 200,
                  height: 280,
                  child: Center(child: Text('BACK')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _faceVisible(WidgetTester tester, String label) {
    final text = find.text(label);
    expect(text, findsOneWidget);
    final opacityFinder = find.ancestor(
      of: text,
      matching: find.byType(Opacity),
    );
    final opacity = tester.widget<Opacity>(opacityFinder.first);
    return opacity.opacity > 0.5;
  }

  testWidgets('tap left half flips when enableDragFlip is false',
      (tester) async {
    await tester.pumpWidget(card(enableDragFlip: false));
    await tester.pumpAndSettle();

    expect(_faceVisible(tester, 'FRONT'), isTrue);
    expect(_faceVisible(tester, 'BACK'), isFalse);

    final rect = tester.getRect(find.byType(TurnableYAxisCard));
    await tester.tapAt(Offset(rect.left + 20, rect.center.dy));
    await tester.pumpAndSettle();

    expect(_faceVisible(tester, 'BACK'), isTrue);
    expect(_faceVisible(tester, 'FRONT'), isFalse);
  });

  testWidgets('horizontal drag does not flip when enableDragFlip is false',
      (tester) async {
    await tester.pumpWidget(card(enableDragFlip: false));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(TurnableYAxisCard));
    await tester.dragFrom(rect.center, const Offset(-120, 0));
    await tester.pumpAndSettle();

    expect(_faceVisible(tester, 'FRONT'), isTrue);
    expect(_faceVisible(tester, 'BACK'), isFalse);
  });

  testWidgets('horizontal drag flips when enableDragFlip is true',
      (tester) async {
    await tester.pumpWidget(card(enableDragFlip: true));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(TurnableYAxisCard));
    await tester.dragFrom(rect.center, const Offset(-160, 0));
    await tester.pumpAndSettle();

    expect(_faceVisible(tester, 'BACK'), isTrue);
    expect(_faceVisible(tester, 'FRONT'), isFalse);
  });
}
