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
  countryCode: 'US',
  state: 'Montana',
  geologicalFormation: 'Hell Creek Formation',
  latitude: 46.8797,
  longitude: -110.3626,
  collectionName: 'Hell Creek site 12',
  collectionDates: '1902',
  collectionType: 'taxonomic',
  occurrenceComments: 'tooth',
  stratcomments: 'Found in sandstone lens.',
  lithdescript: 'channel sandstone',
  composition: 'hydroxyapatite',
  architecture: 'compact or dense',
  fragmentation: 'unabraded',
  description: 'Famous Hell Creek tyrannosaur locality.',
  collectors: 'Barnum Brown',
  museum: 'AMNH',
  family: 'Tyrannosauridae',
  presMode: 'body',
  preservationQuality: 'good',
  abundValue: 1,
  abundUnit: 'specimens',
  minAgeMa: 66,
  maxAgeMa: 68,
  earlyInterval: 'Maastrichtian',
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
    expect(find.text('Occurrence No #100001'), findsOneWidget);
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

  testWidgets('FossilCardBack renders stored fields with clear labels',
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

    expect(find.text('Tyrannosaurus rex'), findsWidgets);
    expect(find.text('OCCURRENCE NO'), findsOneWidget);
    expect(find.text('100001'), findsOneWidget);
    expect(find.text('DINOSAUR'), findsOneWidget);
    expect(find.text('IDENTIFIED NAME'), findsOneWidget);
    expect(find.text('FAMILY'), findsOneWidget);
    expect(find.text('COUNTRY CODE'), findsOneWidget);
    expect(find.text('GEOLOGICAL FORMATION'), findsOneWidget);
    expect(find.text('LATITUDE'), findsOneWidget);
    expect(find.text('LONGITUDE'), findsOneWidget);
    expect(find.text('EARLY INTERVAL'), findsOneWidget);
    expect(find.text('MIN AGE (MA)'), findsOneWidget);
    expect(find.text('MAX AGE (MA)'), findsOneWidget);
    expect(find.text('COLLECTION TYPE'), findsOneWidget);
    expect(find.text('OCCURRENCE COMMENTS'), findsOneWidget);
    expect(find.text('COMPOSITION'), findsOneWidget);
    expect(find.text('ARCHITECTURE'), findsOneWidget);
    expect(find.text('FRAGMENTATION'), findsOneWidget);
    expect(find.text('STRATIGRAPHY COMMENTS'), findsOneWidget);
    expect(find.text('LITHOLOGY'), findsOneWidget);
    expect(find.text('ABUNDANCE VALUE'), findsOneWidget);
    expect(find.text('ABUNDANCE UNIT'), findsOneWidget);
    expect(find.text('PRESERVATION QUALITY'), findsOneWidget);
    expect(find.text('Hell Creek Formation'), findsOneWidget);
    expect(find.text('COLLECTION NAME'), findsOneWidget);
    expect(find.text('Tooth'), findsOneWidget);
    expect(find.text('Barnum Brown'), findsOneWidget);
    expect(find.text('DESCRIPTION'), findsOneWidget);
    expect(find.textContaining('Famous Hell Creek'), findsOneWidget);
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
