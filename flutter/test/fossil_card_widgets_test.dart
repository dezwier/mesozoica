import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/fossil.dart';
import 'package:mesozoica/widgets/cards/dinosaur_card_image.dart';
import 'package:mesozoica/widgets/cards/fossil_card_back.dart';
import 'package:mesozoica/widgets/cards/fossil_card_front.dart';
import 'package:mesozoica/widgets/cards/fossil_card_image.dart';
import 'package:mesozoica/widgets/cards/fossil_turnable_card.dart';

const _fixture = FossilSummary(
  id: 100001,
  dinosaurId: 1,
  dinosaurName: 'Tyrannosaurus',
  identifiedName: 'Tyrannosaurus rex',
  state: 'Montana',
  geologicalFormation: 'Hell Creek Formation',
  latitude: 46.8797,
  longitude: -110.3626,
  collectionDates: '1902',
  stratcomments: 'Found in sandstone lens.',
  description: 'Famous Hell Creek tyrannosaur locality.',
  collectors: 'Barnum Brown',
  presMode: 'body',
  preservationQuality: 'good',
  dinosaurMainImageUrl:
      'https://mesozoica-production.up.railway.app/media/dinosaurs/Tyrannosaurus.webp',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FossilCardFront renders fossil image, dino inset, and title',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              child: FossilCardFront(fossil: _fixture),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(FossilCardImage), findsOneWidget);
    expect(find.byType(DinosaurCardImage), findsOneWidget);
    expect(find.text('Tyrannosaurus rex'), findsOneWidget);
    expect(find.text('LOCATION'), findsNothing);
  });

  testWidgets('FossilCardImage uses network image for curated URL',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 500,
              child: FossilCardImage(
                imageUrl:
                    'https://mesozoica-production.up.railway.app/media/fossils/100001.webp',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });

  testWidgets('FossilCardBack renders location and collection fields',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              child: FossilCardBack(fossil: _fixture),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Tyrannosaurus rex'), findsOneWidget);
    expect(find.text('STATE'), findsOneWidget);
    expect(find.text('FORMATION'), findsOneWidget);
    expect(find.text('COORDINATES'), findsOneWidget);
    expect(find.text('COLLECTION DATES'), findsOneWidget);
    expect(find.text('COMMENTS'), findsOneWidget);
    expect(find.text('COLLECTORS'), findsOneWidget);
    expect(find.text('PRESERVATION MODE'), findsOneWidget);
    expect(find.text('QUALITY'), findsOneWidget);
    expect(find.text('Montana'), findsOneWidget);
    expect(find.text('Hell Creek Formation'), findsOneWidget);
    expect(find.text('Barnum Brown'), findsOneWidget);
  });

  testWidgets('FossilTurnableCard composes front and back faces',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              child: FossilTurnableCard(fossil: _fixture),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(FossilCardFront), findsWidgets);
    expect(find.byType(FossilCardBack), findsWidgets);
    expect(find.text('Tyrannosaurus rex'), findsWidgets);
  });
}
