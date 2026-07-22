import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../models/dinosaur.dart';
import 'display_text.dart';
import 'fractal_tree_layout.dart';

/// A genus card waiting for non-overlapping placement.
class FractalGenusCardCandidate {
  const FractalGenusCardCandidate({
    required this.node,
    required this.dinosaur,
    required this.anchor,
    required this.priority,
    required this.screenSize,
  });

  final FractalLayoutNode node;
  final DinosaurSummary dinosaur;
  final Offset anchor;
  final double priority;
  final Size screenSize;
}

/// A genus card positioned in screen pixels relative to its anchor.
class PlacedGenusCard {
  const PlacedGenusCard({
    required this.candidate,
    required this.screenOffset,
  });

  final FractalGenusCardCandidate candidate;
  final Offset screenOffset;

  Rect treeRect(double zoomScale) {
    final z = zoomScale.clamp(0.001, 500.0);
    return Rect.fromLTWH(
      candidate.anchor.dx + screenOffset.dx / z,
      candidate.anchor.dy + screenOffset.dy / z,
      candidate.screenSize.width / z,
      candidate.screenSize.height / z,
    );
  }
}

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

/// A label positioned in screen pixels relative to its anchor.
class PlacedLabel {
  const PlacedLabel({
    required this.candidate,
    required this.screenOffset,
  });

  final FractalLabelCandidate candidate;
  final Offset screenOffset;

  Rect treeRect(double zoomScale) {
    final tp = candidate.textPainter;
    final z = zoomScale.clamp(0.001, 500.0);
    return Rect.fromLTWH(
      candidate.anchor.dx + screenOffset.dx / z,
      candidate.anchor.dy + screenOffset.dy / z,
      tp.width / z,
      tp.height / z,
    );
  }
}

/// Picks and places labels for the visible viewport without overlap.
class FractalLabelPlacer {
  const FractalLabelPlacer({
    this.labelPadding = 3,
  });

  final double labelPadding;

  /// Base font sizes at zoom scale 1.0 (logical pixels).
  static const double genusBaseFontSize = 15;
  static const double cladeBaseFontSize = 12;

  /// Sublinear exponent — labels grow with zoom, but much less than 1:1.
  static const double labelZoomExponent = 0.25;

  /// Scales label size with zoom so text grows as you zoom in.
  static double zoomScaledScreenFontSize({
    required double baseFontSize,
    required double zoomScale,
    double minSize = 8,
    double maxSize = 22,
  }) {
    final z = zoomScale.clamp(0.08, 50);
    return (baseFontSize * math.pow(z, labelZoomExponent)).clamp(minSize, maxSize);
  }

  static double genusScreenFontSizeFor(double zoomScale) =>
      zoomScaledScreenFontSize(
        baseFontSize: genusBaseFontSize,
        zoomScale: zoomScale,
      );

  static double cladeScreenFontSizeFor(double zoomScale) =>
      zoomScaledScreenFontSize(
        baseFontSize: cladeBaseFontSize,
        zoomScale: zoomScale,
      );

  /// Converts screen pixels to tree-space units for a given [zoomScale].
  static double treeUnits(double screenPixels, double zoomScale) =>
      screenPixels / zoomScale.clamp(0.001, 500.0);

  static double minScreenLengthForLabel(double zoomScale) {
    return (10 / zoomScale.clamp(0.05, 200)).clamp(3, 24);
  }

  /// Collects label candidates visible in [visibleTreeRect].
  List<FractalLabelCandidate> collectCandidates({
    required FractalLayoutNode root,
    required Rect visibleTreeRect,
    required double zoomScale,
    required TextStyle genusStyle,
    required TextStyle cladeStyle,
    Set<FractalLayoutNode> excludeNodes = const {},
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
          if (!excludeNodes.contains(node)) {
            final screenLen = FractalLodPolicy.screenLength(
              node.branchLength,
              zoomScale,
            );
            if (screenLen >= minScreenLen) {
              final isGenus = node.isGenus;
              final style = isGenus ? genusStyle : cladeStyle;

              final textPainter = TextPainter(
                text: TextSpan(
                  text: displayTaxonName(node.label),
                  style: style,
                ),
                textDirection: TextDirection.ltr,
              )..layout();

              final priority = _priority(
                node: node,
                screenLen: screenLen,
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
        text: TextSpan(
          text: displayTaxonName(root.label),
          style: cladeStyle,
        ),
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

    candidates.sort((a, b) {
      final byPriority = b.priority.compareTo(a.priority);
      if (byPriority != 0) return byPriority;
      final byY = a.anchor.dy.compareTo(b.anchor.dy);
      if (byY != 0) return byY;
      return a.anchor.dx.compareTo(b.anchor.dx);
    });
    return candidates;
  }

  /// Collects genus nodes eligible for inline dino cards.
  List<FractalGenusCardCandidate> collectGenusCardCandidates({
    required FractalLayoutNode root,
    required Rect visibleTreeRect,
    required double zoomScale,
    required double viewportWidth,
  }) {
    final candidates = <FractalGenusCardCandidate>[];
    final cardSize =
        FractalLodPolicy.genusCardScreenSize(viewportWidth, zoomScale);
    final expandedVisible =
        visibleTreeRect.inflate(visibleTreeRect.shortestSide * 0.15);

    void walk(FractalLayoutNode node) {
      if (node.parentPosition != null) {
        final collapsed = FractalLodPolicy.shouldCollapse(
          branchLength: node.branchLength,
          zoomScale: zoomScale,
          hasChildren: node.hasChildren,
        );

        if (!collapsed &&
            node.isGenus &&
            node.treeNode.dinosaurs.isNotEmpty &&
            expandedVisible.contains(node.position) &&
            FractalLodPolicy.shouldShowGenusCard(
              branchLength: node.branchLength,
              zoomScale: zoomScale,
              isGenus: true,
            )) {
          final screenLen = FractalLodPolicy.screenLength(
            node.branchLength,
            zoomScale,
          );
          candidates.add(
            FractalGenusCardCandidate(
              node: node,
              dinosaur: node.treeNode.dinosaurs.first,
              anchor: node.position,
              priority: screenLen * 20 + 300,
              screenSize: cardSize,
            ),
          );
        }

        if (collapsed) return;
      }

      for (final child in node.children) {
        walk(child);
      }
    }

    walk(root);

    candidates.sort((a, b) {
      final byPriority = b.priority.compareTo(a.priority);
      if (byPriority != 0) return byPriority;
      final byY = a.anchor.dy.compareTo(b.anchor.dy);
      if (byY != 0) return byY;
      return a.anchor.dx.compareTo(b.anchor.dx);
    });
    return candidates;
  }

  /// Returns placed genus cards centered on each anchor when space allows.
  List<PlacedGenusCard> placeGenusCardsWithoutOverlap(
    List<FractalGenusCardCandidate> candidates, {
    required double zoomScale,
    double cardPadding = 12,
  }) {
    final placed = <Rect>[];
    final result = <PlacedGenusCard>[];
    final z = zoomScale.clamp(0.001, 500.0);
    final padTree = cardPadding / z;

    for (final candidate in candidates) {
      final halfW = candidate.screenSize.width / 2;
      final halfH = candidate.screenSize.height / 2;
      final screenOffset = Offset(-halfW, -halfH);
      final treeRect = Rect.fromLTWH(
        candidate.anchor.dx + screenOffset.dx / z,
        candidate.anchor.dy + screenOffset.dy / z,
        candidate.screenSize.width / z,
        candidate.screenSize.height / z,
      );

      if (_overlapsAny(treeRect.inflate(padTree), placed)) continue;

      placed.add(treeRect.inflate(padTree));
      result.add(
        PlacedGenusCard(candidate: candidate, screenOffset: screenOffset),
      );
    }
    return result;
  }

  /// Builds a single genus card centered on [node] (e.g. tap-to-reveal).
  PlacedGenusCard placedGenusCardForNode({
    required FractalLayoutNode node,
    required DinosaurSummary dinosaur,
    required double viewportWidth,
    required double zoomScale,
  }) {
    final cardSize =
        FractalLodPolicy.genusCardScreenSize(viewportWidth, zoomScale);
    final halfW = cardSize.width / 2;
    final halfH = cardSize.height / 2;
    return PlacedGenusCard(
      candidate: FractalGenusCardCandidate(
        node: node,
        dinosaur: dinosaur,
        anchor: node.position,
        priority: 1000,
        screenSize: cardSize,
      ),
      screenOffset: Offset(-halfW, -halfH),
    );
  }

  Set<FractalLayoutNode> genusCardNodes(List<PlacedGenusCard> placedCards) {
    return placedCards.map((card) => card.candidate.node).toSet();
  }

  double _priority({
    required FractalLayoutNode node,
    required double screenLen,
  }) {
    var score = screenLen * 12;
    if (node.isGenus) score += 200;
    if (node.depth <= 1) score += 80;
    if (node.depth <= 3) score += 30;
    return score;
  }

  /// Returns placed labels with screen-pixel offsets from each anchor.
  List<PlacedLabel> placeWithoutOverlap(
    List<FractalLabelCandidate> candidates, {
    required double zoomScale,
    List<Rect> avoidTreeRects = const [],
  }) {
    final placed = <Rect>[...avoidTreeRects];
    final result = <PlacedLabel>[];
    final z = zoomScale.clamp(0.001, 500.0);
    final padTree = labelPadding / z;

    for (final candidate in candidates) {
      final screenOffset = _findOpenOffset(candidate, placed, zoomScale: z);
      if (screenOffset == null) continue;

      final treeRect = Rect.fromLTWH(
        candidate.anchor.dx + screenOffset.dx / z,
        candidate.anchor.dy + screenOffset.dy / z,
        candidate.textPainter.width / z,
        candidate.textPainter.height / z,
      );
      placed.add(treeRect.inflate(padTree));
      result.add(
        PlacedLabel(candidate: candidate, screenOffset: screenOffset),
      );
    }
    return result;
  }

  Offset? _findOpenOffset(
    FractalLabelCandidate candidate,
    List<Rect> placedTree, {
    required double zoomScale,
  }) {
    final tp = candidate.textPainter;
    final w = tp.width;
    final h = tp.height;
    final anchor = candidate.anchor;
    final isRoot = candidate.node.parentPosition == null;
    final padTree = labelPadding / zoomScale;

    final offsets = isRoot
        ? [const Offset(0, 12)]
        : candidate.isGenus
            ? [
                Offset(-w / 2, -20 - h),
                Offset(-w / 2, 14),
                Offset(-w - 12, -h / 2),
                Offset(14, -h / 2),
                Offset(-w / 2, -32 - h),
                Offset(-w / 2, 26),
              ]
            : [
                Offset(-w / 2, -18 - h),
                Offset(-w / 2, 10),
                Offset(-w - 8, -h / 2),
                Offset(8, -h / 2),
                Offset(-w / 2, -28 - h),
                Offset(-w / 2, 22),
                Offset(-w / 2 - 12, -18 - h),
                Offset(w / 2 + 12, -18 - h),
              ];

    for (final screenOffset in offsets) {
      final treeRect = Rect.fromLTWH(
        anchor.dx + screenOffset.dx / zoomScale,
        anchor.dy + screenOffset.dy / zoomScale,
        w / zoomScale,
        h / zoomScale,
      );
      if (!_overlapsAny(treeRect.inflate(padTree), placedTree)) {
        return screenOffset;
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
