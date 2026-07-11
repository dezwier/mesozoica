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
}
