import 'dinosaur.dart';
import '../utils/display_text.dart';

/// A node in the merged phylogenetic trie built from per-dinosaur cladograms.
class PhyloTreeNode {
  PhyloTreeNode({
    required this.name,
    required this.rankKey,
    required this.depth,
    List<DinosaurSummary>? dinosaurs,
    List<PhyloTreeNode>? children,
  })  : dinosaurs = dinosaurs ?? [],
        children = children ?? [];

  final String name;
  final String rankKey;
  final int depth;
  final List<DinosaurSummary> dinosaurs;
  final List<PhyloTreeNode> children;

  bool get isGenus => rankKey == 'genus' || dinosaurs.isNotEmpty;

  int get leafCount {
    if (children.isEmpty) {
      return dinosaurs.isEmpty ? 1 : dinosaurs.length;
    }
    return children.fold(0, (sum, child) => sum + child.leafCount);
  }

  int get maxDescendantDepth {
    if (children.isEmpty) return depth;
    var maxDepth = depth;
    for (final child in children) {
      maxDepth = maxDepth > child.maxDescendantDepth
          ? maxDepth
          : child.maxDescendantDepth;
    }
    return maxDepth;
  }

  /// Branch nodes first (shallowest subtree, then A–Z), then genus leaves A–Z.
  static int compareChildDisplayOrder(PhyloTreeNode a, PhyloTreeNode b) {
    final aIsBranch = a.children.isNotEmpty;
    final bIsBranch = b.children.isNotEmpty;
    if (aIsBranch != bIsBranch) {
      return aIsBranch ? -1 : 1;
    }
    if (aIsBranch) {
      final nesting = a.maxDescendantDepth.compareTo(b.maxDescendantDepth);
      if (nesting != 0) return nesting;
    }
    return taxonMergeKey(a.name).compareTo(taxonMergeKey(b.name));
  }

  void sortChildrenRecursively() {
    children.sort(compareChildDisplayOrder);
    for (final child in children) {
      child.sortChildrenRecursively();
    }
  }

  PhyloTreeNode? findChildByName(String childName) {
    final key = taxonMergeKey(childName);
    for (final child in children) {
      if (taxonMergeKey(child.name) == key) return child;
    }
    return null;
  }
}

/// Result of merging all dinosaur cladograms into a single trie.
class PhyloTreeBuildResult {
  const PhyloTreeBuildResult({
    required this.root,
    required this.placedCount,
    required this.unplacedCount,
    required this.totalGenera,
  });

  final PhyloTreeNode root;
  final int placedCount;
  final int unplacedCount;
  final int totalGenera;
}
