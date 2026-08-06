import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/dinosaur.dart';
import 'package:mesozoica/models/phylo_tree.dart';
import 'package:mesozoica/widgets/tree/fractal_label_placer.dart';
import 'package:mesozoica/widgets/tree/fractal_tree_layout.dart';

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
  test('zoomScaledScreenFontSize grows with zoom', () {
    expect(
      FractalLabelPlacer.zoomScaledScreenFontSize(
        baseFontSize: 20,
        zoomScale: 2,
      ),
      greaterThan(
        FractalLabelPlacer.zoomScaledScreenFontSize(
          baseFontSize: 20,
          zoomScale: 0.5,
        ),
      ),
    );
  });

  test('zoomScaledScreenFontSize grows sublinearly with zoom', () {
    final atZoom2 = FractalLabelPlacer.zoomScaledScreenFontSize(
      baseFontSize: 20,
      zoomScale: 2,
    );
    expect(atZoom2, lessThan(20 * 2));
    expect(atZoom2, greaterThan(20));
  });

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
    final placed = placer.placeWithoutOverlap([
      candidate,
      candidate,
      candidate,
    ], zoomScale: 1);

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
    expect(placed[0].treeRect(1).overlaps(placed[1].treeRect(1)), isFalse);
  });

  test('placedGenusCardForNode centers card on node anchor', () {
    const placer = FractalLabelPlacer();
    final node = _node(
      name: 'Tyrannosaurus',
      position: const Offset(120, 80),
      isGenus: true,
    );
    final placed = placer.placedGenusCardForNode(
      node: node,
      dinosaur: const DinosaurSummary(
        id: 1,
        name: 'Tyrannosaurus',
        wikipediaTitle: 'Tyrannosaurus',
      ),
      viewportWidth: 390,
      zoomScale: 4,
    );

    expect(placed.candidate.anchor, const Offset(120, 80));
    expect(placed.screenOffset.dx, lessThan(0));
    expect(placed.screenOffset.dy, lessThan(0));
  });

  test(
    'collectCandidates is stable for the same viewport at different pans',
    () {
      const style = TextStyle(fontSize: 12);
      final child = FractalLayoutNode(
        treeNode: PhyloTreeNode(name: 'Child', rankKey: 'clade', depth: 1),
        position: const Offset(120, 120),
        parentPosition: const Offset(100, 100),
        branchPath: null,
        branchLength: 80,
        strokeWidth: 4,
        depth: 1,
        isGenus: false,
        children: const [],
      );
      final root = FractalLayoutNode(
        treeNode: PhyloTreeNode(name: 'Root', rankKey: 'clade', depth: 0),
        position: const Offset(100, 100),
        parentPosition: null,
        branchPath: null,
        branchLength: 0,
        strokeWidth: 4,
        depth: 0,
        isGenus: false,
        children: [child],
      );

      const placer = FractalLabelPlacer();
      const visible = Rect.fromLTWH(80, 80, 80, 80);
      const zoom = 1.0;

      final first = placer.collectCandidates(
        root: root,
        visibleTreeRect: visible,
        zoomScale: zoom,
        genusStyle: style,
        cladeStyle: style,
      );
      final second = placer.collectCandidates(
        root: root,
        visibleTreeRect: visible,
        zoomScale: zoom,
        genusStyle: style,
        cladeStyle: style,
      );

      expect(
        first.map((candidate) => candidate.anchor).toList(),
        second.map((candidate) => candidate.anchor).toList(),
      );
    },
  );
}
