import '../models/dinosaur.dart';
import '../models/phylo_tree.dart';
import 'display_text.dart';

/// Merges per-dinosaur cladogram lineages into a single phylogenetic trie.
class PhyloTreeBuilder {
  const PhyloTreeBuilder();

  PhyloTreeBuildResult build(List<DinosaurSummary> dinosaurs) {
    final root = PhyloTreeNode(name: 'Dinosauria', rankKey: 'clade', depth: 0);

    var placedCount = 0;
    var unplacedCount = 0;
    var totalGenera = 0;

    for (final dinosaur in dinosaurs) {
      final nodes = dinosaur.cladogramNodes();
      if (nodes.isEmpty) {
        unplacedCount++;
        continue;
      }

      _insertPath(root, nodes, dinosaur);
      placedCount++;
      totalGenera++;
    }

    root.sortChildrenRecursively();

    // Collapse single-child chains so the visible root is the LCA of owned
    // (placed) dinosaurs rather than always Dinosauria.
    final visibleRoot = _pruneToOwnedLca(root);

    return PhyloTreeBuildResult(
      root: visibleRoot,
      placedCount: placedCount,
      unplacedCount: unplacedCount,
      totalGenera: totalGenera,
    );
  }

  /// Walks down while there is exactly one child and no dinos on the node.
  PhyloTreeNode _pruneToOwnedLca(PhyloTreeNode root) {
    var current = root;
    while (current.children.length == 1 && current.dinosaurs.isEmpty) {
      current = current.children.single;
    }
    if (!identical(current, root)) {
      current.redepth();
    }
    return current;
  }

  void _insertPath(
    PhyloTreeNode root,
    List<CladogramNode> nodes,
    DinosaurSummary dinosaur,
  ) {
    var current = root;
    var startIndex = 0;

    if (nodes.isNotEmpty &&
        nodes.first.name.toLowerCase() == root.name.toLowerCase()) {
      startIndex = 1;
    }

    for (var i = startIndex; i < nodes.length; i++) {
      final node = nodes[i];
      final isLast = i == nodes.length - 1;
      final name = canonicalTaxonName(node.name);
      if (name.isEmpty) continue;

      var child = current.findChildByName(name);
      if (child == null) {
        child = PhyloTreeNode(
          name: name,
          rankKey: node.rankKey,
          depth: current.depth + 1,
        );
        current.children.add(child);
      }

      if (isLast) {
        child.dinosaurs.add(dinosaur);
      }

      current = child;
    }
  }
}
