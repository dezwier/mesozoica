import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/dinosaur.dart';
import 'package:mesozoica/services/phylo_tree_builder.dart';

DinosaurSummary _dino({
  required int id,
  required String name,
  required Map<String, dynamic> cladogram,
}) {
  return DinosaurSummary(
    id: id,
    name: name,
    wikipediaTitle: name,
    cladogram: cladogram,
  );
}

void main() {
  const builder = PhyloTreeBuilder();

  test('merges dinosaurs sharing a common lineage path', () {
    final result = builder.build([
      _dino(
        id: 1,
        name: 'Tyrannosaurus',
        cladogram: {
          'clade': 'Dinosauria',
          'clade_2': 'Theropoda',
          'family': 'Tyrannosauridae',
          'genus': 'Tyrannosaurus',
        },
      ),
      _dino(
        id: 2,
        name: 'Velociraptor',
        cladogram: {
          'clade': 'Dinosauria',
          'clade_2': 'Theropoda',
          'family': 'Dromaeosauridae',
          'genus': 'Velociraptor',
        },
      ),
    ]);

    expect(result.placedCount, 2);
    expect(result.unplacedCount, 0);
    expect(result.root.name, 'Dinosauria');

    final theropoda = result.root.findChildByName('Theropoda');
    expect(theropoda, isNotNull);
    expect(theropoda!.children, hasLength(2));

    final tyrannosauridae = theropoda.findChildByName('Tyrannosauridae');
    expect(tyrannosauridae, isNotNull);
    final tyrannosaurus = tyrannosauridae!.findChildByName('Tyrannosaurus');
    expect(tyrannosaurus?.dinosaurs.single.id, 1);
  });

  test('creates Saurischia and Ornithischia split when present in data', () {
    final result = builder.build([
      _dino(
        id: 1,
        name: 'Tyrannosaurus',
        cladogram: {
          'clade': 'Dinosauria',
          'clade_2': 'Saurischia',
          'clade_3': 'Theropoda',
          'genus': 'Tyrannosaurus',
        },
      ),
      _dino(
        id: 2,
        name: 'Triceratops',
        cladogram: {
          'clade': 'Dinosauria',
          'clade_2': 'Ornithischia',
          'clade_3': 'Ceratopsia',
          'genus': 'Triceratops',
        },
      ),
    ]);

    expect(result.root.children, hasLength(2));
    expect(result.root.findChildByName('Saurischia'), isNotNull);
    expect(result.root.findChildByName('Ornithischia'), isNotNull);
  });

  test('skips dinosaurs without Dinosauria in cladogram', () {
    final result = builder.build([
      _dino(
        id: 1,
        name: 'Mystery',
        cladogram: {
          'kingdom': 'Animalia',
          'phylum': 'Chordata',
        },
      ),
      _dino(
        id: 2,
        name: 'Tyrannosaurus',
        cladogram: {
          'clade': 'Dinosauria',
          'genus': 'Tyrannosaurus',
        },
      ),
    ]);

    expect(result.placedCount, 1);
    expect(result.unplacedCount, 1);
    expect(result.totalGenera, 1);
    expect(result.root.findChildByName('Tyrannosaurus')?.dinosaurs.single.id, 2);
  });

  test('attaches multiple records under the same genus name', () {
    final result = builder.build([
      _dino(
        id: 1,
        name: 'Tyrannosaurus',
        cladogram: {
          'clade': 'Dinosauria',
          'genus': 'Tyrannosaurus',
        },
      ),
      _dino(
        id: 2,
        name: 'Tyrannosaurus (alt)',
        cladogram: {
          'clade': 'Dinosauria',
          'genus': 'Tyrannosaurus',
        },
      ),
    ]);

    final genusNode = result.root.findChildByName('Tyrannosaurus');
    expect(genusNode?.dinosaurs, hasLength(2));
    expect(genusNode?.dinosaurs.map((d) => d.id), containsAll([1, 2]));
  });

  test('merges clade variants with different whitespace or markers', () {
    final result = builder.build([
      _dino(
        id: 1,
        name: 'Brachiosaurus',
        cladogram: {
          'clade': 'Dinosauria',
          'clade_2': 'Saurischia',
          'clade_3': 'Sauropodomorpha',
          'genus': 'Brachiosaurus',
        },
      ),
      _dino(
        id: 2,
        name: 'Diplodocus',
        cladogram: {
          'clade': 'Dinosauria',
          'clade_2': 'Saurischia',
          'clade_3': ' † Sauropodomorpha ',
          'genus': 'Diplodocus',
        },
      ),
      _dino(
        id: 3,
        name: 'Allosaurus',
        cladogram: {
          'clade': 'Dinosauria',
          'clade_2': 'Saurischia',
          'clade_3': 'Theropoda',
          'genus': 'Allosaurus',
        },
      ),
    ]);

    final saurischia = result.root.findChildByName('Saurischia');
    expect(saurischia, isNotNull);
    expect(saurischia!.children, hasLength(2));

    final sauropodomorpha = saurischia.findChildByName('Sauropodomorpha');
    expect(sauropodomorpha, isNotNull);
    expect(sauropodomorpha!.children, hasLength(2));
    expect(
      sauropodomorpha.children.map((child) => child.name),
      containsAll(['Brachiosaurus', 'Diplodocus']),
    );
  });
}
