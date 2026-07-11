import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/dinosaur.dart';
import 'package:mesozoica/widgets/cards/dinosaur_card_back.dart';
import 'package:mesozoica/widgets/cards/dinosaur_card_front.dart';
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
              width: 320,
              child: DinosaurCardFront(dinosaur: _fixture),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsWidgets);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(find.text('TYRANNOSAURUS REX'), findsOneWidget);
    expect(find.text('LOCATION'), findsOneWidget);
    expect(find.text('TIME PERIOD'), findsOneWidget);
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

    expect(find.text('TYRANNOSAURUS REX'), findsOneWidget);
    expect(find.text('LOCATION'), findsNothing);
    expect(find.text('TIME PERIOD'), findsNothing);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.text('CLADOGRAM'), findsOneWidget);
    expect(find.text('CLADE'), findsNWidgets(2));
    expect(find.text('FAMILY'), findsOneWidget);
    expect(find.text('GENUS'), findsOneWidget);
    expect(
      find.textContaining('largest terrestrial predators'),
      findsOneWidget,
    );
  });

  testWidgets('DinosaurTurnableCard composes front and back', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: DinosaurTurnableCard(dinosaur: _fixture),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(DinosaurCardFront), findsWidgets);
    expect(find.byType(DinosaurCardBack), findsWidgets);
  });
}
