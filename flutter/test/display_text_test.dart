import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/utils/display_text.dart';

void main() {
  test('displayTaxonName strips extinct markers and uncertainty suffixes', () {
    expect(displayTaxonName('† Tyrannosaurus'), 'Tyrannosaurus');
    expect(displayTaxonName('Velociraptor (?)'), 'Velociraptor');
    expect(displayTaxonName('Coelophysis (Osborn, 1905)'), 'Coelophysis');
    expect(displayTaxonName('Hybrid × name'), 'Hybrid name');
    expect(canonicalTaxonName('  Sauropodomorpha '), 'Sauropodomorpha');
    expect(taxonMergeKey('†Sauropodomorpha'), 'sauropodomorpha');
  });

  test('displayTaxonName strips trailing author and year', () {
    expect(displayTaxonName('Allosaurinae Marsh , 1878'), 'Allosaurinae');
    expect(displayTaxonName('Brachiosaurus Riggs, 1903'), 'Brachiosaurus');
    expect(
      displayTaxonName('Abelisaurus Bonaparte et al., 1990'),
      'Abelisaurus',
    );
  });

  test('toTitleCase splits underscores and capitalizes words', () {
    expect(toTitleCase('vulcanic_ash'), 'Vulcanic Ash');
    expect(toTitleCase('Jurassic'), 'Jurassic');
    expect(toTitleCase('sandstone'), 'Sandstone');
    expect(toTitleCase('  mixed_CASE rock '), 'Mixed Case Rock');
  });
}
