import 'dart:math' as math;
import 'dart:ui';

import '../models/phylo_tree.dart';

/// A node in the precomputed fractal fern layout.
class FractalLayoutNode {
  const FractalLayoutNode({
    required this.treeNode,
    required this.position,
    required this.parentPosition,
    required this.branchPath,
    required this.branchLength,
    required this.strokeWidth,
    required this.depth,
    required this.isGenus,
    required this.children,
  });

  final PhyloTreeNode treeNode;
  final Offset position;
  final Offset? parentPosition;
  final Path? branchPath;
  final double branchLength;
  final double strokeWidth;
  final int depth;
  final bool isGenus;
  final List<FractalLayoutNode> children;

  String get label => treeNode.name;

  bool get hasChildren => children.isNotEmpty;
}

/// Polar wedge fractal layout — OneZoom-style, full tree in fixed coordinates.
class FractalTreeLayout {
  static const fullCircleFan = math.pi * 2;

  FractalTreeLayout({
    this.baseLength = 84,
    this.decay = 0.83,
    this.rootFanRadians = fullCircleFan,
    this.branchCurveFactor = 0.21,
    this.siblingAngleGap = 0.02,
    this.minStrokeWidth = 1.2,
    this.maxStrokeWidth = 10,
    this.boundsPadding = 48,
  });

  final double baseLength;
  final double decay;
  final double rootFanRadians;
  final double branchCurveFactor;
  /// Extra radians inserted between sibling wedges to widen the fan.
  final double siblingAngleGap;
  final double minStrokeWidth;
  final double maxStrokeWidth;
  final double boundsPadding;

  late FractalLayoutNode _root;
  late Rect _bounds;
  late int _maxLeaves;
  late List<FractalLayoutNode> _genusNodes;

  FractalLayoutNode get root => _root;
  Rect get bounds => _bounds;
  List<FractalLayoutNode> get genusNodes => _genusNodes;

  void compute(PhyloTreeNode root) {
    _maxLeaves = math.max(1, root.leafCount);
    _genusNodes = [];

    final halfFan = rootFanRadians / 2;
    _root = _layoutNode(
      node: root,
      angleMin: -halfFan,
      angleMax: halfFan,
      depth: 0,
      parentPos: Offset.zero,
    );

    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;

    void walk(FractalLayoutNode node) {
      minX = math.min(minX, node.position.dx);
      maxX = math.max(maxX, node.position.dx);
      minY = math.min(minY, node.position.dy);
      maxY = math.max(maxY, node.position.dy);
      if (node.isGenus) _genusNodes.add(node);
      for (final child in node.children) {
        walk(child);
      }
    }

    walk(_root);

    _bounds = Rect.fromLTRB(
      minX - boundsPadding,
      minY - boundsPadding,
      maxX + boundsPadding,
      maxY + boundsPadding,
    );
  }

  FractalLayoutNode _layoutNode({
    required PhyloTreeNode node,
    required double angleMin,
    required double angleMax,
    required int depth,
    required Offset parentPos,
  }) {
    final isRoot = depth == 0;
    final position = isRoot
        ? parentPos
        : _positionFrom(parentPos, angleMin, angleMax, depth);
    final branchLength =
        isRoot ? 0.0 : _branchLengthForDepth(depth);
    final branchPath = isRoot
        ? null
        : _buildBranchPath(parentPos, position, depth);

    final isGenus = node.isGenus && node.dinosaurs.isNotEmpty;
    final strokeWidth = _strokeWidthFor(node.leafCount);

    if (node.children.isEmpty) {
      return FractalLayoutNode(
        treeNode: node,
        position: position,
        parentPosition: isRoot ? null : parentPos,
        branchPath: branchPath,
        branchLength: branchLength,
        strokeWidth: strokeWidth,
        depth: depth,
        isGenus: isGenus,
        children: const [],
      );
    }

    final totalLeaves = node.leafCount;
    final childCount = node.children.length;
    final wedgeSpan = angleMax - angleMin;
    final totalGap = siblingAngleGap * math.max(0, childCount - 1);
    final allocatable = math.max(0, wedgeSpan - totalGap);

    var currentAngle = angleMin;
    final childLayouts = <FractalLayoutNode>[];
    final sortedChildren = [...node.children]
      ..sort(PhyloTreeNode.compareChildDisplayOrder);

    for (final child in sortedChildren) {
      final span = allocatable * child.leafCount / totalLeaves;
      childLayouts.add(
        _layoutNode(
          node: child,
          angleMin: currentAngle,
          angleMax: currentAngle + span,
          depth: depth + 1,
          parentPos: position,
        ),
      );
      currentAngle += span;
      if (child != sortedChildren.last) {
        currentAngle += siblingAngleGap;
      }
    }

    return FractalLayoutNode(
      treeNode: node,
      position: position,
      parentPosition: isRoot ? null : parentPos,
      branchPath: branchPath,
      branchLength: branchLength,
      strokeWidth: strokeWidth,
      depth: depth,
      isGenus: isGenus,
      children: childLayouts,
    );
  }

  double _branchLengthForDepth(int depth) =>
      baseLength * math.pow(decay, depth - 1);

  Offset _positionFrom(
    Offset parent,
    double angleMin,
    double angleMax,
    int depth,
  ) {
    final mid = (angleMin + angleMax) / 2;
    final len = _branchLengthForDepth(depth);
    return parent + Offset(math.sin(mid) * len, -math.cos(mid) * len);
  }

  Path _buildBranchPath(Offset from, Offset to, int depth) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 1) {
      return Path()
        ..moveTo(from.dx, from.dy)
        ..lineTo(to.dx, to.dy);
    }

    final ux = dx / length;
    final uy = dy / length;
    final perpX = -uy;
    final perpY = ux;
    final depthCurveBoost = 1.0 + depth * 0.04;
    final bow = length * branchCurveFactor * depthCurveBoost * 0.45;

    final control1 = Offset(
      from.dx + ux * length * 0.28 + perpX * bow,
      from.dy + uy * length * 0.28 + perpY * bow,
    );
    final control2 = Offset(
      from.dx + ux * length * 0.72 + perpX * bow,
      from.dy + uy * length * 0.72 + perpY * bow,
    );

    return Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        to.dx,
        to.dy,
      );
  }

  double _strokeWidthFor(int leafCount) {
    final ratio = math.sqrt(leafCount / _maxLeaves);
    return minStrokeWidth + (maxStrokeWidth - minStrokeWidth) * ratio;
  }
}

/// Zoom-based level-of-detail thresholds for fractal rendering.
class FractalLodPolicy {
  const FractalLodPolicy._();

  static const double collapseThreshold = 4;
  static const double labelThreshold = 18;
  static const double genusTapThreshold = 12;

  /// Converts on-screen pixels to tree-space units at [zoomScale].
  static double treeUnits(double screenPixels, double zoomScale) =>
      screenPixels / zoomScale.clamp(0.001, 500);

  /// Grows slightly when zoomed in (+12% per decade, max +40%).
  static double subtleZoomBoost(double zoomScale) {
    return (1.0 + math.log(zoomScale.clamp(0.25, 200)) / math.ln10 * 0.12)
        .clamp(1.0, 1.4);
  }

  /// Nodes grow more noticeably when zoomed in (+30% per decade, max +100%).
  static double nodeZoomBoost(double zoomScale) {
    return (1.0 + math.log(zoomScale.clamp(1.0, 200)) / math.ln10 * 0.30)
        .clamp(1.0, 2.0);
  }

  static double treeUnitsWithBoost({
    required double screenPixels,
    required double zoomScale,
  }) {
    return treeUnits(screenPixels * subtleZoomBoost(zoomScale), zoomScale);
  }

  static double nodeTreeUnitsWithBoost({
    required double screenPixels,
    required double zoomScale,
  }) {
    return treeUnits(screenPixels * nodeZoomBoost(zoomScale), zoomScale);
  }

  static double screenLength(double branchLength, double zoomScale) =>
      branchLength * zoomScale;

  static bool shouldCollapse({
    required double branchLength,
    required double zoomScale,
    required bool hasChildren,
  }) {
    if (!hasChildren) return false;
    return screenLength(branchLength, zoomScale) < collapseThreshold;
  }

  static bool shouldShowLabel({
    required double branchLength,
    required double zoomScale,
  }) {
    return screenLength(branchLength, zoomScale) >= labelThreshold;
  }

  static bool isGenusTappable({
    required double branchLength,
    required double zoomScale,
    required bool isGenus,
  }) {
    if (!isGenus) return false;
    return screenLength(branchLength, zoomScale) >= genusTapThreshold;
  }

  static double leafBlobScreenRadius({
    required int leafCount,
    required int maxLeaves,
    required bool isGenus,
  }) {
    final base = (isGenus ? 5.5 : 4.0) +
        3.5 * math.sqrt(leafCount / math.max(1, maxLeaves));
    return base;
  }

  static double leafBlobRadius({
    required int leafCount,
    required double branchLength,
    required double zoomScale,
    required int maxLeaves,
    required bool isGenus,
  }) {
    return nodeTreeUnitsWithBoost(
      screenPixels: leafBlobScreenRadius(
        leafCount: leafCount,
        maxLeaves: maxLeaves,
        isGenus: isGenus,
      ),
      zoomScale: zoomScale,
    );
  }
}
