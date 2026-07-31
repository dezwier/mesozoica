import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/widgets/dino/dinosaur_wikipedia_view.dart';

void main() {
  test('wikipediaArticleUri encodes title spaces as underscores', () {
    expect(
      wikipediaArticleUri('Tyrannosaurus rex').toString(),
      'https://en.wikipedia.org/wiki/Tyrannosaurus_rex',
    );
  });

  test('wikipediaMobileArticleUri uses mobile host', () {
    expect(
      wikipediaMobileArticleUri('Velociraptor').toString(),
      'https://en.m.wikipedia.org/wiki/Velociraptor',
    );
  });
}
