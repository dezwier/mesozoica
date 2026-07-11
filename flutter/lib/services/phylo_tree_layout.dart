import 'dart:math' as math;
import 'dart:ui';

import '../models/phylo_tree.dart';

/// A laid-out node ready for painting and hit-testing.
class PhyloLayoutNode {
  const PhyloLayoutNode({
    required this.treeNode,
    required this.position,
    required this.branchPath,
    required this.strokeWidth,
    required this.hitTarget,
    required this.depth,
    required this.isGenus,
  });

  final PhyloTreeNode treeNode;
  final Offset position;
  final Path? branchPath;
  final double strokeWidth;
  final Rect hitTarget;
  final int depth;
  final bool isGenus;

  String get label => treeNode.name;
}

/// Bottom-up fern layout for a phylogenetic trie.
class PhyloTreeLayout {
  PhyloTreeLayout({
    this.leafSpacing = 48,
    this.levelSpacing = 72,
    this.branchCurveFactor = 0.35,
    this.minStrokeWidth = 1.2,
    this.maxStrokeWidth = 8,
    this.hitTargetRadius = 14,
  });

  final double leafSpacing;
  final double levelSpacing;
  final double branchCurveFactor;
  final double minStrokeWidth;
  final double maxStrokeWidth;
  final double hitTargetRadius;

  late Rect _bounds;
  late List<PhyloLayoutNode> _nodes;
  late int _maxDepth;
  late int _maxLeaves;

  Rect get bounds => _bounds;
  List<PhyloLayoutNode> get nodes => _nodes;

  /// Bounding box of nodes up to [maxDepth] (for macro fit / semantic zoom).
  Rect boundsForMaxDepth(int maxDepth, {bool includeGenus = false}) {
    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;

    for (final node in _nodes) {
      if (node.isGenus && !includeGenus) continue;
      if (node.depth > maxDepth) continue;

      minX = math.min(minX, node.position.dx - hitTargetRadius);
      maxX = math.max(maxX, node.position.dx + hitTargetRadius);
      minY = math.min(minY, node.position.dy - hitTargetRadius);
      maxY = math.max(maxY, node.position.dy + hitTargetRadius);
    }

    if (minX == double.infinity) return _bounds;

    return Rect.fromLTRB(
      minX - 32,
      minY - 32,
      maxX + 32,
      maxY + 48,
    );
  }

  void compute(PhyloTreeNode root) {
    _maxDepth = _measureMaxDepth(root);
    _maxLeaves = math.max(1, root.leafCount);

    final positions = <PhyloTreeNode, Offset>{};
    var leafIndex = 0.0;
    _assignLeafPositions(root, positions, () => leafIndex++);

    final maxLeafIndex = math.max(1, root.leafCount - 1);
    final treeWidth = maxLeafIndex * leafSpacing;
    final centerX = treeWidth / 2;
    positions[root] = Offset(centerX, _yForDepth(root.depth));

    _nodes = [];
    _assignLayoutNodes(root, positions, null);

    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;

    for (final node in _nodes) {
      minX = math.min(minX, node.position.dx - hitTargetRadius);
      maxX = math.max(maxX, node.position.dx + hitTargetRadius);
      minY = math.min(minY, node.position.dy - hitTargetRadius);
      maxY = math.max(maxY, node.position.dy + hitTargetRadius);
    }

    _bounds = Rect.fromLTRB(
      minX - 32,
      minY - 32,
      maxX + 32,
      maxY + 48,
    );
  }

  double _yForDepth(int depth) => (_maxDepth - depth) * levelSpacing;

  int _measureMaxDepth(PhyloTreeNode node) {
    if (node.children.isEmpty) return node.depth;
    return node.children.map(_measureMaxDepth).reduce(math.max);
  }

  void _assignLeafPositions(
    PhyloTreeNode node,
    Map<PhyloTreeNode, Offset> positions,
    double Function() nextLeafIndex,
  ) {
    if (node.children.isEmpty) {
      final index = nextLeafIndex();
      positions[node] = Offset(index * leafSpacing, _yForDepth(node.depth));
      return;
    }

    for (final child in node.children) {
      _assignLeafPositions(child, positions, nextLeafIndex);
    }

    final childPositions =
        node.children.map((c) => positions[c]!).toList(growable: false);
    final avgX = childPositions.fold(0.0, (sum, p) => sum + p.dx) /
        childPositions.length;
    positions[node] = Offset(avgX, _yForDepth(node.depth));
  }

  void _assignLayoutNodes(
    PhyloTreeNode node,
    Map<PhyloTreeNode, Offset> positions,
    PhyloTreeNode? parent,
  ) {
    final position = positions[node]!;
    Path? branchPath;
    var strokeWidth = maxStrokeWidth;

    if (parent != null) {
      final parentPos = positions[parent]!;
      branchPath = _buildBranchPath(parentPos, position);
      strokeWidth = _strokeWidthFor(parent);
    }

    final isGenus = node.isGenus && node.dinosaurs.isNotEmpty;
    final hitRadius = isGenus ? hitTargetRadius * 1.2 : hitTargetRadius;

    _nodes.add(
      PhyloLayoutNode(
        treeNode: node,
        position: position,
        branchPath: branchPath,
        strokeWidth: strokeWidth,
        hitTarget: Rect.fromCircle(center: position, radius: hitRadius),
        depth: node.depth,
        isGenus: isGenus,
      ),
    );

    for (final child in node.children) {
      _assignLayoutNodes(child, positions, node);
    }
  }

  Path _buildBranchPath(Offset from, Offset to) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 1) {
      return Path()
        ..moveTo(from.dx, from.dy)
        ..lineTo(to.dx, to.dy);
    }

    final perpX = -dy / length;
    final perpY = dx / length;
    final curveOffset = length * branchCurveFactor;
    final sign = from.dx <= to.dx ? 1.0 : -1.0;

    final control = Offset(
      (from.dx + to.dx) / 2 + perpX * curveOffset * sign,
      (from.dy + to.dy) / 2 + perpY * curveOffset * sign * 0.3,
    );

    return Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy);
  }

  double _strokeWidthFor(PhyloTreeNode node) {
    final ratio = node.leafCount / _maxLeaves;
    return minStrokeWidth + (maxStrokeWidth - minStrokeWidth) * ratio;
  }
}
