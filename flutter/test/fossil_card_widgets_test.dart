import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/fossil.dart';
import 'package:mesozoica/widgets/cards/dinosaur_card_image.dart';
import 'package:mesozoica/widgets/cards/fossil_card_back.dart';
import 'package:mesozoica/widgets/cards/fossil_card_front.dart';
import 'package:mesozoica/widgets/cards/fossil_card_image.dart';
import 'package:mesozoica/widgets/cards/fossil_turnable_card.dart';
import 'package:mesozoica/widgets/cards/geologic_timeline.dart';
import 'package:mesozoica/widgets/cards/site_card_image.dart';
import 'package:mesozoica/widgets/fossil/fossil_record_drawer.dart';

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
  llmDescription: 'A well-preserved tyrannosaur tooth from the Hell Creek Formation.',
  llmCategory: 'Tooth',
  llmSubcategory: 'Crown fragment',
  llmPreservationQuality: 'Excellent',
  llmCompleteness: 'Partial',
  llmRockType: 'Sandstone',
  llmImpCategory: 'body',
  llmImpSubcategory: 'teeth',
  llmImpPreservationQuality: 'good',
  llmImpCompleteness: 'isolated_element',
  llmImpRockType: 'sandstone',
  dinosaurMainImageUrl:
      'https://mesozoica-production.up.railway.app/media/dinosaurs/Tyrannosaurus.webp',
  siteId: 50001,
  siteMainImageUrl:
      'https://mesozoica-production.up.railway.app/media/site-types/1.png',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FossilSummary.displaySubtitle is occurrence for archive', () {
    expect(_fixture.displaySubtitle, 'Occurrence No #100001');
  });

  test('FossilSummary.displaySubtitle lists field attributes and depth', () {
    const field = FossilSummary(
      id: 200001,
      dinosaurId: 1,
      dinosaurName: 'Tyrannosaurus',
      dataSource: 'field',
      llmImpCategory: 'body',
      llmImpSubcategory: 'teeth',
      llmImpPreservationQuality: 'good',
      llmImpCompleteness: 'isolated_element',
      depthCm: 45,
    );
    expect(
      field.displaySubtitle,
      'Body, Teeth, Good, Isolated Element, 45cm',
    );
  });

  testWidgets('FossilCardFront renders fossil image, title, and llm description',
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
    expect(find.byType(SiteCardImage), findsNothing);
    expect(find.byType(DinosaurCardImage), findsNothing);
    expect(find.text('Tyrannosaurus rex'), findsOneWidget);
    expect(find.text('Occurrence No #100001'), findsNothing);
    expect(find.text('DINOSAUR'), findsNothing);
    expect(find.text('ROCK TYPE'), findsNothing);
    expect(find.text('PERIOD'), findsNothing);
    expect(
      find.textContaining('well-preserved tyrannosaur tooth'),
      findsOneWidget,
    );
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

  testWidgets('FossilCardBack renders timeline, attributes, and related thumbs',
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
    expect(find.text('Occurrence No #100001'), findsOneWidget);
    expect(find.text('TIME'), findsNothing);
    expect(find.text('RECORD'), findsNothing);
    expect(find.byType(GeologicTimeline), findsOneWidget);
    expect(find.byType(SiteCardImage), findsOneWidget);
    expect(find.byType(DinosaurCardImage), findsOneWidget);
    expect(find.text('Hell Creek Formation'), findsWidgets);
    expect(find.text('CATEGORY'), findsOneWidget);
    expect(find.text('SUB CATEGORY'), findsOneWidget);
    expect(find.text('PRESERVATION QUALITY'), findsOneWidget);
    expect(find.text('COMPLETENESS'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
    expect(find.text('Teeth'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Isolated_element'), findsOneWidget);
    expect(find.text('Tooth'), findsNothing);
    expect(find.text('Excellent'), findsNothing);
    expect(find.text('Partial'), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(find.text('OCCURRENCE NO'), findsNothing);
  });

  testWidgets('FossilCardBack info button opens record drawer', (tester) async {
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

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.byType(FossilRecordDrawer), findsOneWidget);

    final drawer = find.byType(FossilRecordDrawer);
    expect(find.descendant(of: drawer, matching: find.text('OCCURRENCE NO')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('100001')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('LLM DESCRIPTION')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('LLM CATEGORY')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('LLM ROCK TYPE')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('Sandstone')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('Tooth')), findsWidgets);
    expect(find.descendant(of: drawer, matching: find.text('DINOSAUR')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('IDENTIFIED NAME')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('FAMILY')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('COUNTRY CODE')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('GEOLOGICAL FORMATION')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('LATITUDE')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('LONGITUDE')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('EARLY INTERVAL')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('MIN AGE (MA)')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('MAX AGE (MA)')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('COLLECTION TYPE')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('OCCURRENCE COMMENTS')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('COMPOSITION')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('ARCHITECTURE')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('FRAGMENTATION')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('STRATIGRAPHY COMMENTS')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('LITHOLOGY')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('ABUNDANCE VALUE')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('ABUNDANCE UNIT')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('PRESERVATION QUALITY')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('COLLECTION NAME')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('Barnum Brown')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('DESCRIPTION')), findsOneWidget);
    expect(
      find.descendant(
        of: drawer,
        matching: find.textContaining('Famous Hell Creek'),
      ),
      findsOneWidget,
    );
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
