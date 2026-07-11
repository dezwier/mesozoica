import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/phylo_tree.dart';
import 'package:mesozoica/services/fractal_label_placer.dart';
import 'package:mesozoica/services/fractal_tree_layout.dart';

FractalLayoutNode _node({
  required String name,
  required Offset position,
  Offset? parentPosition,
  bool isGenus = false,
}) {
  return FractalLayoutNode(
    treeNode: PhyloTreeNode(
      name: name,
      rankKey: isGenus ? 'genus' : 'clade',
      depth: parentPosition == null ? 0 : 1,
    ),
    position: position,
    parentPosition: parentPosition,
    branchPath: null,
    branchLength: 80,
    strokeWidth: 4,
    depth: parentPosition == null ? 0 : 1,
    isGenus: isGenus,
    children: const [],
  );
}

void main() {
  test('minScreenLengthForLabel drops as zoom increases', () {
    expect(
      FractalLabelPlacer.minScreenLengthForLabel(0.2),
      greaterThan(FractalLabelPlacer.minScreenLengthForLabel(1.5)),
    );
  });

  test('placeWithoutOverlap skips labels that cannot fit', () {
    const style = TextStyle(fontSize: 12);
    final tp = TextPainter(
      text: const TextSpan(text: 'Overlap', style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    final candidate = FractalLabelCandidate(
      node: _node(name: 'A', position: const Offset(100, 100)),
      textPainter: tp,
      anchor: const Offset(100, 100),
      priority: 10,
      isGenus: false,
    );

    const placer = FractalLabelPlacer(labelPadding: 4);
    final placed = placer.placeWithoutOverlap(
      [candidate, candidate, candidate],
      zoomScale: 1,
    );

    expect(placed, hasLength(1));
  });

  test('placeWithoutOverlap allows separated labels', () {
    const style = TextStyle(fontSize: 12);
    TextPainter painter(String text) {
      return TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
    }

    const placer = FractalLabelPlacer();
    final placed = placer.placeWithoutOverlap([
      FractalLabelCandidate(
        node: _node(
          name: 'Alpha',
          position: const Offset(50, 50),
          isGenus: true,
        ),
        textPainter: painter('Alpha'),
        anchor: const Offset(50, 50),
        priority: 100,
        isGenus: true,
      ),
      FractalLabelCandidate(
        node: _node(
          name: 'Beta',
          position: const Offset(250, 50),
          isGenus: true,
        ),
        textPainter: painter('Beta'),
        anchor: const Offset(250, 50),
        priority: 90,
        isGenus: true,
      ),
    ], zoomScale: 1);

    expect(placed, hasLength(2));
    expect(placed[0].$2.overlaps(placed[1].$2), isFalse);
  });
}
