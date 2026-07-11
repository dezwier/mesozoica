import 'phylo_tree_layout.dart';

/// Semantic zoom tiers for the phylogenetic fern tree.
enum PhyloDetailLevel {
  /// Root plus two clade tiers (~3 taxonomy levels).
  macro,

  /// Intermediate subclades and families.
  meso,

  /// Deep taxonomy before genera.
  fine,

  /// Genus leaves and full detail.
  genus,
}

/// Maps [InteractiveViewer] scale to how much of the trie is drawn.
class PhyloZoomPolicy {
  PhyloZoomPolicy._();

  /// Default visible depth on first load (0 = root → 3 levels total).
  static const int initialMaxDepth = 2;

  static PhyloDetailLevel detailLevel(double scale) {
    if (scale < 0.45) return PhyloDetailLevel.macro;
    if (scale < 0.75) return PhyloDetailLevel.meso;
    if (scale < 1.35) return PhyloDetailLevel.fine;
    return PhyloDetailLevel.genus;
  }

  static int maxVisibleDepth(double scale) {
    return switch (detailLevel(scale)) {
      PhyloDetailLevel.macro => 2,
      PhyloDetailLevel.meso => 4,
      PhyloDetailLevel.fine => 6,
      PhyloDetailLevel.genus => 999,
    };
  }

  static bool isNodeVisible(PhyloLayoutNode node, double scale) {
    if (node.isGenus) {
      return detailLevel(scale) == PhyloDetailLevel.genus;
    }
    return node.depth <= maxVisibleDepth(scale);
  }

  static bool hasHiddenDescendants(PhyloLayoutNode node, double scale) {
    if (node.isGenus) return false;
    return node.treeNode.maxDescendantDepth > maxVisibleDepth(scale);
  }

  /// Minimum scale needed to reveal taxonomy down to [depth].
  static double minScaleForDepth(int depth) {
    if (depth <= 2) return 0.05;
    if (depth <= 4) return 0.45;
    if (depth <= 6) return 0.75;
    return 1.35;
  }
}
