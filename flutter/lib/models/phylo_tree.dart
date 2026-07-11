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
