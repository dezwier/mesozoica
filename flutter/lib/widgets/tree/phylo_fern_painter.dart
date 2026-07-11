import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/phylo_tree_layout.dart';
import '../../services/phylo_zoom_policy.dart';

class PhyloFernPainter extends CustomPainter {
  PhyloFernPainter({
    required this.layout,
    required this.branchColor,
    required this.labelColor,
    required this.labelMutedColor,
    required this.rootGlowColor,
    required this.zoomScale,
  });

  final PhyloTreeLayout layout;
  final Color branchColor;
  final Color labelColor;
  final Color labelMutedColor;
  final Color rootGlowColor;
  final double zoomScale;

  @override
  void paint(Canvas canvas, Size size) {
    final nodes = layout.nodes;
    if (nodes.isEmpty) return;

    canvas.translate(-layout.bounds.left, -layout.bounds.top);

    final rootNode = nodes.first;
    final rootPaint = Paint()
      ..shader = ui.Gradient.radial(
        rootNode.position,
        48,
        [
          rootGlowColor.withValues(alpha: 0.25),
          rootGlowColor.withValues(alpha: 0),
        ],
      );
    canvas.drawCircle(rootNode.position, 48, rootPaint);

    for (final node in nodes) {
      if (!PhyloZoomPolicy.isNodeVisible(node, zoomScale)) continue;

      final path = node.branchPath;
      if (path == null) continue;

      final paint = Paint()
        ..color = branchColor.withValues(
          alpha: 0.35 + 0.55 * (node.strokeWidth / layout.maxStrokeWidth),
        )
        ..strokeWidth = node.strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      canvas.drawPath(path, paint);
    }

    for (final node in nodes) {
      if (!PhyloZoomPolicy.isNodeVisible(node, zoomScale)) continue;

      final isGenus = node.isGenus;
      final fontSize = isGenus ? 11.0 : (node.depth <= 2 ? 13.0 : 10.0);
      final color = isGenus ? labelColor : labelMutedColor;
      final fontWeight = node.depth <= 1 ? FontWeight.w700 : FontWeight.w500;

      final textPainter = TextPainter(
        text: TextSpan(
          text: node.label,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: fontWeight,
            letterSpacing: 0.2,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 120);

      final offset = Offset(
        node.position.dx - textPainter.width / 2,
        node.position.dy - (isGenus ? 22 : 18),
      );
      textPainter.paint(canvas, offset);

      if (isGenus) {
        final dotPaint = Paint()..color = branchColor;
        canvas.drawCircle(node.position, 3.5, dotPaint);
      } else if (PhyloZoomPolicy.hasHiddenDescendants(node, zoomScale)) {
        _paintCollapsedBadge(canvas, node);
      }
    }
  }

  void _paintCollapsedBadge(Canvas canvas, PhyloLayoutNode node) {
    final hiddenLeaves = node.treeNode.leafCount;
    final label = hiddenLeaves > 99 ? '99+' : '$hiddenLeaves';

    const badgeHeight = 14.0;
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: labelColor,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final badgeWidth = math.max(18.0, textPainter.width + 8);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(node.position.dx, node.position.dy + 10),
        width: badgeWidth,
        height: badgeHeight,
      ),
      const Radius.circular(7),
    );

    canvas.drawRRect(
      rect,
      Paint()..color = branchColor.withValues(alpha: 0.85),
    );
    textPainter.paint(
      canvas,
      Offset(
        rect.center.dx - textPainter.width / 2,
        rect.center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant PhyloFernPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.branchColor != branchColor ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.labelMutedColor != labelMutedColor ||
        oldDelegate.rootGlowColor != rootGlowColor ||
        PhyloZoomPolicy.detailLevel(oldDelegate.zoomScale) !=
            PhyloZoomPolicy.detailLevel(zoomScale);
  }
}

/// Computes an initial matrix that fits [bounds] (tree coordinates) in [viewportSize].
/// [layoutBounds] is the full canvas extent used to map tree → canvas space.
Matrix4 fitTreeTransform({
  required Rect bounds,
  required Rect layoutBounds,
  required Size viewportSize,
  double bottomPadding = 48,
}) {
  if (bounds.isEmpty || viewportSize.isEmpty) return Matrix4.identity();

  final canvasCenterX = bounds.center.dx - layoutBounds.left;
  final canvasBottom = bounds.bottom - layoutBounds.top;
  final contentWidth = bounds.width;
  final contentHeight = bounds.height;
  final scaleX = viewportSize.width / contentWidth;
  final scaleY = (viewportSize.height - bottomPadding) / contentHeight;
  final scale = math.min(scaleX, scaleY).clamp(0.05, 2.0);

  final viewCenterX = viewportSize.width / 2;
  final viewBottom = viewportSize.height - bottomPadding;

  final tx = viewCenterX - canvasCenterX * scale;
  final ty = viewBottom - canvasBottom * scale;

  return Matrix4.identity()
    ..setEntry(0, 0, scale)
    ..setEntry(1, 1, scale)
    ..setEntry(0, 3, tx)
    ..setEntry(1, 3, ty);
}
