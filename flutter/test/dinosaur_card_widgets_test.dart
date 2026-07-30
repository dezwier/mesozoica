import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/controllers/auth_controller.dart';
import 'package:mesozoica/controllers/catalog_mode_controller.dart';
import 'package:mesozoica/models/dinosaur.dart';
import 'package:mesozoica/widgets/cards/dinosaur_card_back.dart';
import 'package:mesozoica/widgets/cards/dinosaur_card_edge_facts.dart';
import 'package:mesozoica/widgets/cards/dinosaur_card_fossil_map.dart';
import 'package:mesozoica/widgets/cards/dinosaur_card_front.dart';
import 'package:mesozoica/widgets/cards/dinosaur_card_image.dart';
import 'package:mesozoica/widgets/cards/dinosaur_turnable_card.dart';
import 'package:provider/provider.dart';

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

Widget _wrapDinoCard(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => CatalogModeController()),
      ChangeNotifierProvider(create: (_) => AuthController()),
    ],
    child: MaterialApp(home: Scaffold(body: Center(child: child))),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DinosaurCardFront renders art, title, and description at bottom',
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
    expect(find.byIcon(Icons.info_outline), findsNothing);
    expect(find.text('Tyrannosaurus rex'), findsOneWidget);
    expect(
      find.textContaining('largest terrestrial predators'),
      findsOneWidget,
    );
    expect(find.byType(DinosaurCardEdgeFacts), findsNothing);
    expect(find.textContaining('Hell Creek Formation'), findsNothing);
    expect(find.textContaining('Late Cretaceous'), findsNothing);
    expect(find.text('LOCATION'), findsNothing);
    expect(find.text('PERIOD'), findsNothing);
  });

  testWidgets('DinosaurCardFront hides description when showFacts is false',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              child: DinosaurCardFront(
                dinosaur: _fixture,
                showFacts: false,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(DinosaurCardEdgeFacts), findsNothing);
    expect(
      find.textContaining('largest terrestrial predators'),
      findsNothing,
    );
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

  testWidgets('DinosaurCardBack renders horizontal timeline, map, and cladogram',
      (tester) async {
    await tester.pumpWidget(
      _wrapDinoCard(
        const SizedBox(
          width: 320,
          child: DinosaurCardBack(dinosaur: _fixture),
        ),
      ),
    );

    expect(find.text('Tyrannosaurus rex'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(find.text('LOCATION'), findsNothing);
    expect(find.text('PERIOD'), findsOneWidget);
    expect(find.text('DIET'), findsOneWidget);
    expect(find.text('MASS'), findsOneWidget);
    expect(find.text('LENGTH'), findsOneWidget);
    expect(find.text('TIME'), findsNothing);
    expect(find.text('CLADOGRAM'), findsOneWidget);
    expect(find.text('FOSSIL RECORD'), findsNothing);
    expect(find.text('Triassic'), findsOneWidget);
    expect(find.text('Jurassic'), findsOneWidget);
    expect(find.text('Cretaceous'), findsOneWidget);
    expect(find.text('252 Ma'), findsOneWidget);
    expect(find.text('66 Ma'), findsOneWidget);
    expect(find.text('CLADE'), findsNWidgets(2));
    expect(find.text('FAMILY'), findsOneWidget);
    expect(find.text('GENUS'), findsOneWidget);
    expect(
      find.textContaining('largest terrestrial predators'),
      findsNothing,
    );
    expect(find.byType(DinosaurCardFossilMap), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('DinosaurCardBack shows Reconstructed subtitle for inventory',
      (tester) async {
    final inventory = DinosaurSummary(
      id: 99,
      dinosaurTypeId: 1,
      name: 'Tyrannosaurus rex',
      wikipediaTitle: 'Tyrannosaurus',
      birth: 68,
      death: 66,
      period: 'Late Cretaceous',
      createdAt: DateTime.now().toUtc().subtract(const Duration(days: 2)),
      version: 'Original',
    );

    await tester.pumpWidget(
      _wrapDinoCard(
        SizedBox(
          width: 320,
          child: DinosaurCardBack(dinosaur: inventory),
        ),
      ),
    );

    expect(find.text('Reconstructed 2d ago'), findsOneWidget);
    expect(find.text('Original - Reconstructed 2d ago'), findsNothing);
    expect(find.text('#99'), findsNothing);
    expect(find.text('#99, Original'), findsNothing);
    expect(find.text('Tyrannosaurus'), findsNothing);
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
      _wrapDinoCard(
        SizedBox(
          width: 800,
          child: DinosaurTurnableCard(dinosaur: compactFixture),
        ),
      ),
    );

    expect(find.byType(DinosaurCardFront), findsWidgets);
    expect(find.byType(DinosaurCardBack), findsWidgets);
  });
}
