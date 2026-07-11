import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/dinosaur.dart';

void main() {
  test('cladogramLineage preserves infobox order from Dinosauria through genus', () {
    const dino = DinosaurSummary(
      id: 1,
      name: 'Tyrannosaurus',
      wikipediaTitle: 'Tyrannosaurus',
      cladogram: {
        'kingdom': 'Animalia',
        'phylum': 'Chordata',
        'class': 'Reptilia',
        'clade': 'Dinosauria',
        'clade_2': 'Theropoda',
        'family': 'Tyrannosauridae',
        'genus': 'Tyrannosaurus',
        'species': 'T. rex',
      },
    );

    expect(
      dino.cladogramLineage(),
      [
        'Dinosauria',
        'Theropoda',
        'Tyrannosauridae',
        'Tyrannosaurus',
      ],
    );
  });

  test('cladogramLineage returns empty when Dinosauria is absent', () {
    const dino = DinosaurSummary(
      id: 1,
      name: 'Mystery',
      wikipediaTitle: 'Mystery',
      cladogram: {
        'kingdom': 'Animalia',
        'phylum': 'Chordata',
      },
    );

    expect(dino.cladogramLineage(), isEmpty);
  });

  test('cladogramNodes returns rank labels and stops at genus', () {
    const dino = DinosaurSummary(
      id: 1,
      name: 'Tyrannosaurus',
      wikipediaTitle: 'Tyrannosaurus',
      cladogram: {
        'kingdom': 'Animalia',
        'phylum': 'Chordata',
        'class': 'Reptilia',
        'clade': 'Dinosauria',
        'clade_2': 'Theropoda',
        'family': 'Tyrannosauridae',
        'genus': 'Tyrannosaurus',
        'species': 'T. rex',
      },
    );

    final nodes = dino.cladogramNodes();

    expect(nodes, hasLength(4));
    expect(nodes[0].rankLabel, 'CLADE');
    expect(nodes[0].name, 'Dinosauria');
    expect(nodes[1].rankLabel, 'CLADE');
    expect(nodes[1].name, 'Theropoda');
    expect(nodes[2].rankLabel, 'FAMILY');
    expect(nodes[2].name, 'Tyrannosauridae');
    expect(nodes[3].rankLabel, 'GENUS');
    expect(nodes[3].name, 'Tyrannosaurus');
  });

  test('displayPeriod uses single Ma when birth equals death', () {
    const withPeriod = DinosaurSummary(
      id: 1,
      name: 'Example',
      wikipediaTitle: 'Example',
      birth: 70,
      death: 70,
      period: 'Late Cretaceous',
    );
    const withoutPeriod = DinosaurSummary(
      id: 2,
      name: 'Example',
      wikipediaTitle: 'Example',
      birth: 70,
      death: 70,
    );

    expect(withPeriod.displayPeriod, 'Late Cretaceous, 70 Ma');
    expect(withoutPeriod.displayPeriod, '70 Ma');
    expect(withPeriod.displayPeriodName, 'Late Cretaceous');
    expect(withoutPeriod.displayPeriodName, '—');

    const withMaInPeriod = DinosaurSummary(
      id: 3,
      name: 'Example',
      wikipediaTitle: 'Example',
      period: 'Early Cretaceous, 105 - 100 Ma',
    );
    expect(withMaInPeriod.displayPeriodName, 'Early Cretaceous');
  });
}
