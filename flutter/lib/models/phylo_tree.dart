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
  }) : dinosaurs = dinosaurs ?? [],
       children = children ?? [];

  final String name;
  final String rankKey;
  int depth;
  final List<DinosaurSummary> dinosaurs;
  final List<PhyloTreeNode> children;

  /// Reassigns [depth] for this node and all descendants.
  void redepth([int newDepth = 0]) {
    depth = newDepth;
    for (final child in children) {
      child.redepth(newDepth + 1);
    }
  }

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

  /// Levels of internal branching below this node (0 for terminal leaves).
  ///
  /// A branch whose children are all leaves has depth 1; each additional
  /// branch generation below increments by one.
  int get branchNestDepth {
    if (children.isEmpty) return 0;

    var maxBelow = 0;
    for (final child in children) {
      if (child.children.isEmpty) {
        if (maxBelow < 1) maxBelow = 1;
      } else {
        final below = 1 + child.branchNestDepth;
        if (below > maxBelow) maxBelow = below;
      }
    }
    return maxBelow;
  }

  bool get isTerminalLeaf => children.isEmpty;

  /// All leaves first (A–Z), then branches by ascending nest depth (A–Z).
  static int compareChildDisplayOrder(PhyloTreeNode a, PhyloTreeNode b) {
    final aIsLeaf = a.isTerminalLeaf;
    final bIsLeaf = b.isTerminalLeaf;
    if (aIsLeaf != bIsLeaf) {
      return aIsLeaf ? -1 : 1;
    }
    if (aIsLeaf) {
      return taxonMergeKey(a.name).compareTo(taxonMergeKey(b.name));
    }

    final nesting = a.branchNestDepth.compareTo(b.branchNestDepth);
    if (nesting != 0) return nesting;
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
