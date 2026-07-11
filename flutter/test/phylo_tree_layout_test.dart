import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/dinosaur.dart';
import 'package:mesozoica/models/phylo_tree.dart';
import 'package:mesozoica/services/phylo_tree_builder.dart';
import 'package:mesozoica/services/phylo_tree_layout.dart';

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

PhyloTreeNode _buildSampleTree() {
  const builder = PhyloTreeBuilder();
  return builder.build([
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
    _dino(
      id: 3,
      name: 'Stegosaurus',
      cladogram: {
        'clade': 'Dinosauria',
        'clade_2': 'Ornithischia',
        'clade_3': 'Stegosauria',
        'genus': 'Stegosaurus',
      },
    ),
  ]).root;
}

void main() {
  test('leaf spacing is monotonic and parent sits between children', () {
    final root = _buildSampleTree();
    final layout = PhyloTreeLayout(
      leafSpacing: 100,
      levelSpacing: 80,
    )..compute(root);

    final byName = {
      for (final node in layout.nodes) node.label: node,
    };

    final ornithischia = byName['Ornithischia']!;
    final ceratopsia = byName['Ceratopsia']!;
    final stegosauria = byName['Stegosauria']!;
    final triceratops = byName['Triceratops']!;
    final stegosaurus = byName['Stegosaurus']!;

    expect(ceratopsia.position.dx, isNot(stegosauria.position.dx));
    expect(triceratops.position.dx, isNot(stegosaurus.position.dx));

    final childXs = [ceratopsia.position.dx, stegosauria.position.dx]..sort();
    expect(ornithischia.position.dx, closeTo((childXs[0] + childXs[1]) / 2, 0.01));

    expect(byName['Dinosauria']!.position.dy, greaterThan(ornithischia.position.dy));
    expect(ornithischia.position.dy, greaterThan(triceratops.position.dy));
  });

  test('layout bounds encompass all nodes', () {
    final root = _buildSampleTree();
    final layout = PhyloTreeLayout()..compute(root);

    for (final node in layout.nodes) {
      expect(layout.bounds.left, lessThanOrEqualTo(node.position.dx));
      expect(layout.bounds.right, greaterThanOrEqualTo(node.position.dx));
      expect(layout.bounds.top, lessThanOrEqualTo(node.position.dy));
      expect(layout.bounds.bottom, greaterThanOrEqualTo(node.position.dy));
    }
  });
}
