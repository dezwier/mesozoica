import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import 'fractal_tree_layout.dart';

/// A label waiting for non-overlapping placement.
class FractalLabelCandidate {
  const FractalLabelCandidate({
    required this.node,
    required this.textPainter,
    required this.anchor,
    required this.priority,
    required this.isGenus,
  });

  final FractalLayoutNode node;
  final TextPainter textPainter;
  final Offset anchor;
  final double priority;
  final bool isGenus;
}

/// Picks and places labels for the visible viewport without overlap.
class FractalLabelPlacer {
  const FractalLabelPlacer({
    this.labelPadding = 3,
    this.maxLabels = 48,
  });

  final double labelPadding;
  final int maxLabels;

  /// Fixed on-screen font sizes (logical pixels).
  static const double genusScreenFontSize = 13;
  static const double shallowCladeScreenFontSize = 14.5;
  static const double cladeScreenFontSize = 12;
  static const double maxLabelScreenWidth = 130;

  /// Converts screen pixels to tree-space units for a given [zoomScale].
  static double treeUnits(double screenPixels, double zoomScale) =>
      screenPixels / zoomScale.clamp(0.01, 20);

  static double minScreenLengthForLabel(double zoomScale) {
    return (14 / zoomScale.clamp(0.05, 8)).clamp(4, 28);
  }

  /// Collects label candidates visible in [visibleTreeRect].
  List<FractalLabelCandidate> collectCandidates({
    required FractalLayoutNode root,
    required Rect visibleTreeRect,
    required Offset viewportCenterTree,
    required double zoomScale,
    required TextStyle genusStyle,
    required TextStyle cladeStyle,
    required TextStyle shallowCladeStyle,
  }) {
    final candidates = <FractalLabelCandidate>[];
    final minScreenLen = minScreenLengthForLabel(zoomScale);
    final expandedVisible =
        visibleTreeRect.inflate(visibleTreeRect.shortestSide * 0.15);

    void walk(FractalLayoutNode node, {required bool parentExpanded}) {
      if (node.parentPosition != null) {
        final collapsed = FractalLodPolicy.shouldCollapse(
          branchLength: node.branchLength,
          zoomScale: zoomScale,
          hasChildren: node.hasChildren,
        );

        if (!collapsed && expandedVisible.contains(node.position)) {
          final screenLen = FractalLodPolicy.screenLength(
            node.branchLength,
            zoomScale,
          );
          if (screenLen >= minScreenLen) {
            final isGenus = node.isGenus;
            final style = isGenus
                ? genusStyle
                : (node.depth <= 2 ? shallowCladeStyle : cladeStyle);

            final textPainter = TextPainter(
              text: TextSpan(text: node.label, style: style),
              textDirection: TextDirection.ltr,
              maxLines: 1,
              ellipsis: '…',
            )..layout(
                maxWidth: treeUnits(maxLabelScreenWidth, zoomScale),
              );

            final dist = (node.position - viewportCenterTree).distance;
            final priority = _priority(
              node: node,
              screenLen: screenLen,
              distToCenter: dist,
              visibleSize: visibleTreeRect.shortestSide,
            );

            candidates.add(
              FractalLabelCandidate(
                node: node,
                textPainter: textPainter,
                anchor: node.position,
                priority: priority,
                isGenus: isGenus,
              ),
            );
          }
        }

        if (FractalLodPolicy.shouldCollapse(
          branchLength: node.branchLength,
          zoomScale: zoomScale,
          hasChildren: node.hasChildren,
        )) {
          return;
        }
      }

      for (final child in node.children) {
        walk(child, parentExpanded: true);
      }
    }

    walk(root, parentExpanded: true);

    // Root label when visible.
    if (expandedVisible.contains(root.position)) {
      final textPainter = TextPainter(
        text: TextSpan(text: root.label, style: shallowCladeStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      candidates.add(
        FractalLabelCandidate(
          node: root,
          textPainter: textPainter,
          anchor: root.position,
          priority: 10000,
          isGenus: false,
        ),
      );
    }

    candidates.sort((a, b) => b.priority.compareTo(a.priority));
    if (candidates.length > maxLabels) {
      return candidates.sublist(0, maxLabels);
    }
    return candidates;
  }

  double _priority({
    required FractalLayoutNode node,
    required double screenLen,
    required double distToCenter,
    required double visibleSize,
  }) {
    var score = screenLen * 12;
    if (node.isGenus) score += 200;
    if (node.depth <= 1) score += 80;
    if (node.depth <= 3) score += 30;
    score -= (distToCenter / math.max(visibleSize, 1)) * 40;
    return score;
  }

  /// Returns placed labels as (candidate, top-left rect).
  List<(FractalLabelCandidate, Rect)> placeWithoutOverlap(
    List<FractalLabelCandidate> candidates, {
    required double zoomScale,
  }) {
    final placed = <Rect>[];
    final result = <(FractalLabelCandidate, Rect)>[];
    final pad = treeUnits(labelPadding, zoomScale);

    for (final candidate in candidates) {
      final rect = _findOpenRect(candidate, placed, zoomScale: zoomScale);
      if (rect == null) continue;
      placed.add(rect.inflate(pad));
      result.add((candidate, rect));
    }
    return result;
  }

  Rect? _findOpenRect(
    FractalLabelCandidate candidate,
    List<Rect> placed, {
    required double zoomScale,
  }) {
    final tp = candidate.textPainter;
    final w = tp.width;
    final h = tp.height;
    final anchor = candidate.anchor;
    final isRoot = candidate.node.parentPosition == null;
    final pad = treeUnits(labelPadding, zoomScale);
    double s(double screen) => treeUnits(screen, zoomScale);

    final offsets = isRoot
        ? [Offset(0, s(12))]
        : [
            Offset(-w / 2, -s(18) - h),
            Offset(-w / 2, s(10)),
            Offset(-w - s(8), -h / 2),
            Offset(s(8), -h / 2),
            Offset(-w / 2, -s(28) - h),
            Offset(-w / 2, s(22)),
            Offset(-w / 2 - s(12), -s(18) - h),
            Offset(w / 2 + s(12), -s(18) - h),
          ];

    for (final delta in offsets) {
      final rect = Rect.fromLTWH(
        anchor.dx + delta.dx,
        anchor.dy + delta.dy,
        w,
        h,
      );
      if (!_overlapsAny(rect.inflate(pad), placed)) {
        return rect;
      }
    }
    return null;
  }

  bool _overlapsAny(Rect rect, List<Rect> placed) {
    for (final other in placed) {
      if (rect.overlaps(other)) return true;
    }
    return false;
  }
}

/// Maps viewport corners through [transform] into tree coordinates.
Rect visibleTreeRect({
  required Size viewportSize,
  required Matrix4 transform,
  required Rect layoutBounds,
}) {
  if (viewportSize.isEmpty) return Rect.zero;

  final inverse = Matrix4.inverted(transform);
  final corners = [
    MatrixUtils.transformPoint(inverse, Offset.zero),
    MatrixUtils.transformPoint(inverse, Offset(viewportSize.width, 0)),
    MatrixUtils.transformPoint(
      inverse,
      Offset(viewportSize.width, viewportSize.height),
    ),
    MatrixUtils.transformPoint(inverse, Offset(0, viewportSize.height)),
  ];

  var minX = double.infinity;
  var maxX = double.negativeInfinity;
  var minY = double.infinity;
  var maxY = double.negativeInfinity;

  for (final corner in corners) {
    final treeX = corner.dx + layoutBounds.left;
    final treeY = corner.dy + layoutBounds.top;
    minX = math.min(minX, treeX);
    maxX = math.max(maxX, treeX);
    minY = math.min(minY, treeY);
    maxY = math.max(maxY, treeY);
  }

  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

Offset viewportCenterInTree({
  required Size viewportSize,
  required Matrix4 transform,
  required Rect layoutBounds,
}) {
  final inverse = Matrix4.inverted(transform);
  final center = MatrixUtils.transformPoint(
    inverse,
    Offset(viewportSize.width / 2, viewportSize.height / 2),
  );
  return Offset(
    center.dx + layoutBounds.left,
    center.dy + layoutBounds.top,
  );
}
