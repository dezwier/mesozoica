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
}
