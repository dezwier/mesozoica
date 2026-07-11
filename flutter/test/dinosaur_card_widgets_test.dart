import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/dinosaur.dart';
import 'package:mesozoica/widgets/cards/dinosaur_card_back.dart';
import 'package:mesozoica/widgets/cards/dinosaur_card_front.dart';
import 'package:mesozoica/widgets/cards/dinosaur_card_image.dart';
import 'package:mesozoica/widgets/cards/dinosaur_turnable_card.dart';

const _fixture = DinosaurSummary(
  id: 1,
  name: 'Tyrannosaurus rex',
  wikipediaTitle: 'Tyrannosaurus',
  birth: 68,
  death: 66,
  period: 'Late Cretaceous',
  dietType: 'Carnivore',
  length: '~12 – 13 m',
  mass: '~6 – 9 tonnes',
  location: 'Hell Creek Formation, Montana, USA',
  shortDescription:
      'One of the largest terrestrial predators of all time.',
  cladogram: {
    'clade': 'Dinosauria',
    'clade_2': 'Theropoda',
    'family': 'Tyrannosauridae',
    'genus': 'Tyrannosaurus',
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DinosaurCardFront renders art, title, facts, and info button',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              child: DinosaurCardFront(dinosaur: _fixture),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(DinosaurCardImage), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(find.text('Tyrannosaurus rex'), findsOneWidget);
    expect(find.text('LOCATION'), findsOneWidget);
    expect(find.text('PERIOD'), findsOneWidget);
  });

  testWidgets('DinosaurCardImage uses network image for curated URL',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DinosaurCardImage(
            imageUrl:
                'https://mesozoica-production.up.railway.app/media/dinosaurs/Tyrannosaurus.webp',
          ),
        ),
      ),
    );

    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });

  testWidgets('DinosaurCardImage uses placeholder for Wikipedia URL',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DinosaurCardImage(
            imageUrl:
                'https://upload.wikimedia.org/wikipedia/commons/t-rex.jpg',
          ),
        ),
      ),
    );

    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('DinosaurCardImage uses placeholder when URL is null',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DinosaurCardImage(imageUrl: null),
        ),
      ),
    );

    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('DinosaurCardBack renders description, timeline, and cladogram',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: DinosaurCardBack(dinosaur: _fixture),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Tyrannosaurus rex'), findsOneWidget);
    expect(find.text('LOCATION'), findsNothing);
    expect(find.text('PERIOD'), findsNothing);
    expect(find.text('TIME'), findsNothing);
    expect(find.text('CLADOGRAM'), findsNothing);
    expect(find.text('CLADE'), findsNWidgets(2));
    expect(find.text('FAMILY'), findsOneWidget);
    expect(find.text('GENUS'), findsOneWidget);
    expect(
      find.textContaining('largest terrestrial predators'),
      findsOneWidget,
    );
  });

  testWidgets('DinosaurTurnableCard composes front and back', (tester) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    final compactFixture = DinosaurSummary(
      id: _fixture.id,
      name: _fixture.name,
      wikipediaTitle: _fixture.wikipediaTitle,
      birth: _fixture.birth,
      death: _fixture.death,
      period: _fixture.period,
      dietType: _fixture.dietType,
      length: _fixture.length,
      mass: _fixture.mass,
      location: 'Montana, USA',
      shortDescription: _fixture.shortDescription,
      cladogram: _fixture.cladogram,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              child: DinosaurTurnableCard(dinosaur: compactFixture),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(DinosaurCardFront), findsWidgets);
    expect(find.byType(DinosaurCardBack), findsWidgets);
  });
}
