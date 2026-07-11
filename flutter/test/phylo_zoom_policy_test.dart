import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/dinosaur.dart';
import 'package:mesozoica/models/phylo_tree.dart';
import 'package:mesozoica/services/phylo_tree_builder.dart';
import 'package:mesozoica/services/phylo_tree_layout.dart';
import 'package:mesozoica/services/phylo_zoom_policy.dart';

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
  group('PhyloZoomPolicy', () {
    test('macro view shows three taxonomy levels', () {
      expect(PhyloZoomPolicy.maxVisibleDepth(0.2), 2);
      expect(PhyloZoomPolicy.detailLevel(0.2), PhyloDetailLevel.macro);
    });

    test('scale thresholds step through detail levels', () {
      expect(PhyloZoomPolicy.detailLevel(0.5), PhyloDetailLevel.meso);
      expect(PhyloZoomPolicy.detailLevel(1.0), PhyloDetailLevel.fine);
      expect(PhyloZoomPolicy.detailLevel(2.0), PhyloDetailLevel.genus);
    });

    test('genus nodes only appear at genus detail level', () {
      final layout = PhyloTreeLayout()..compute(_sampleRoot());
      final genus = layout.nodes.firstWhere((node) => node.isGenus);

      expect(PhyloZoomPolicy.isNodeVisible(genus, 0.3), isFalse);
      expect(PhyloZoomPolicy.isNodeVisible(genus, 1.5), isTrue);
    });
  });

  test('boundsForMaxDepth is tighter than full layout bounds', () {
    final layout = PhyloTreeLayout()..compute(_sampleRoot());

    final macroBounds = layout.boundsForMaxDepth(PhyloZoomPolicy.initialMaxDepth);
    expect(macroBounds.height, lessThan(layout.bounds.height));
    expect(macroBounds.width, lessThanOrEqualTo(layout.bounds.width));
  });
}

PhyloTreeNode _sampleRoot() {
  const builder = PhyloTreeBuilder();
  return builder.build([
    _dino(
      id: 1,
      name: 'Tyrannosaurus',
      cladogram: {
        'clade': 'Dinosauria',
        'clade_2': 'Saurischia',
        'clade_3': 'Theropoda',
        'clade_4': 'Tyrannosauridae',
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
        'clade_4': 'Ceratopsidae',
        'genus': 'Triceratops',
      },
    ),
  ]).root;
}
