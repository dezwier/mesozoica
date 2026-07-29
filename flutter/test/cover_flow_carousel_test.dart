import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/widgets/common/cover_flow_carousel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CoverFlowCarousel builds focused and side items', (tester) async {
    final focused = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: CoverFlowCarousel(
              itemCount: 5,
              viewportFraction: 0.7,
              itemBuilder: (context, index, isFocused) {
                if (isFocused) focused.add(index);
                return ColoredBox(
                  color: isFocused ? Colors.green : Colors.grey,
                  child: Text('item-$index'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('item-0'), findsOneWidget);
    expect(focused.contains(0), isTrue);
  });

  testWidgets('CoverFlowCarousel onPageChanged fires after drag snap',
      (tester) async {
    final pages = <int>[];
    final key = GlobalKey<CoverFlowCarouselState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: CoverFlowCarousel(
              key: key,
              itemCount: 4,
              viewportFraction: 0.7,
              onPageChanged: pages.add,
              itemBuilder: (context, index, isFocused) {
                return Center(child: Text('card-$index'));
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    key.currentState!.animateToPage(2);
    await tester.pumpAndSettle();

    expect(pages, contains(2));
    expect(find.text('card-2'), findsWidgets);
  });

  testWidgets('CoverFlowCarousel animateToFirst returns to index 0',
      (tester) async {
    final key = GlobalKey<CoverFlowCarouselState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: CoverFlowCarousel(
              key: key,
              itemCount: 3,
              itemBuilder: (context, index, isFocused) {
                return Text(
                  isFocused ? 'focus-$index' : 'side-$index',
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    key.currentState!.animateToPage(2);
    await tester.pumpAndSettle();
    expect(find.text('focus-2'), findsOneWidget);

    key.currentState!.animateToFirst();
    await tester.pumpAndSettle();
    expect(find.text('focus-0'), findsOneWidget);
  });

  testWidgets('strong left fling advances multiple pages', (tester) async {
    final pages = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: CoverFlowCarousel(
              itemCount: 8,
              viewportFraction: 0.7,
              onPageChanged: pages.add,
              itemBuilder: (context, index, isFocused) {
                return Text(isFocused ? 'focus-$index' : 'side-$index');
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Finger swipes left (negative dx) → later cards.
    await tester.fling(
      find.byType(CoverFlowCarousel),
      const Offset(-350, 0),
      2500,
    );
    await tester.pumpAndSettle();

    expect(pages.isNotEmpty, isTrue);
    expect(pages.last, greaterThanOrEqualTo(2));
    expect(find.text('focus-0'), findsNothing);
  });
}
