import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/dinosaur.dart';
import 'package:mesozoica/models/phylo_tree.dart';
import 'package:mesozoica/services/fractal_tree_layout.dart';
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

FractalLayoutNode? _findByName(FractalLayoutNode node, String name) {
  if (node.label == name) return node;
  for (final child in node.children) {
    final found = _findByName(child, name);
    if (found != null) return found;
  }
  return null;
}

void main() {
  test('root is at origin and children spread outward', () {
    final root = _buildSampleTree();
    final layout = FractalTreeLayout()..compute(root);

    expect(layout.root.position, Offset.zero);

    for (final child in layout.root.children) {
      expect(child.position.distance, greaterThan(0));
    }
  });

  test('Saurischia and Ornithischia split under Dinosauria', () {
    final layout = FractalTreeLayout()..compute(_buildSampleTree());

    final saurischia = _findByName(layout.root, 'Saurischia');
    final ornithischia = _findByName(layout.root, 'Ornithischia');

    expect(saurischia, isNotNull);
    expect(ornithischia, isNotNull);
    expect(
      saurischia!.position.dx.sign,
      isNot(ornithischia!.position.dx.sign),
      reason: 'major clades should fan to opposite sides',
    );
  });

  test('internal node is offset from its parent', () {
    final layout = FractalTreeLayout()..compute(_buildSampleTree());
    final theropoda = _findByName(layout.root, 'Theropoda')!;

    expect(
      (theropoda.position - theropoda.parentPosition!).distance,
      greaterThan(0),
    );
  });

  test('bounds encompass all nodes', () {
    final layout = FractalTreeLayout()..compute(_buildSampleTree());

    void walk(FractalLayoutNode node) {
      expect(layout.bounds.left, lessThanOrEqualTo(node.position.dx));
      expect(layout.bounds.right, greaterThanOrEqualTo(node.position.dx));
      expect(layout.bounds.top, lessThanOrEqualTo(node.position.dy));
      expect(layout.bounds.bottom, greaterThanOrEqualTo(node.position.dy));
      for (final child in node.children) {
        walk(child);
      }
    }

    walk(layout.root);
  });

  test('genus nodes are collected for hit testing', () {
    final layout = FractalTreeLayout()..compute(_buildSampleTree());

    expect(layout.genusNodes, hasLength(3));
    expect(
      layout.genusNodes.map((n) => n.label).toSet(),
      containsAll(['Tyrannosaurus', 'Triceratops', 'Stegosaurus']),
    );
  });
}
