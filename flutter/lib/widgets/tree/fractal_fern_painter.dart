import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/fractal_tree_layout.dart';

class FractalFernPainter extends CustomPainter {
  FractalFernPainter({
    required this.layout,
    required this.zoomScale,
    required this.branchColor,
    required this.labelColor,
    required this.labelMutedColor,
    required this.rootGlowColor,
    required this.leafColor,
  });

  final FractalTreeLayout layout;
  final double zoomScale;
  final Color branchColor;
  final Color labelColor;
  final Color labelMutedColor;
  final Color rootGlowColor;
  final Color leafColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(-layout.bounds.left, -layout.bounds.top);

    _paintRootGlow(canvas, layout.root);

    _paintSubtree(
      canvas,
      layout.root,
      parentExpanded: true,
    );
  }

  void _paintRootGlow(Canvas canvas, FractalLayoutNode root) {
    final glowRadius = 56 + layout.maxStrokeWidth * 2;
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        root.position,
        glowRadius,
        [
          rootGlowColor.withValues(alpha: 0.28),
          rootGlowColor.withValues(alpha: 0),
        ],
      );
    canvas.drawCircle(root.position, glowRadius, paint);

    final rootLabel = TextPainter(
      text: TextSpan(
        text: root.label,
        style: TextStyle(
          color: labelColor,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    rootLabel.paint(
      canvas,
      Offset(
        root.position.dx - rootLabel.width / 2,
        root.position.dy + 10,
      ),
    );
  }

  void _paintSubtree(
    Canvas canvas,
    FractalLayoutNode node, {
    required bool parentExpanded,
  }) {
    for (final child in node.children) {
      _paintNode(canvas, child);
    }
  }

  void _paintNode(Canvas canvas, FractalLayoutNode node) {
    final collapsed = FractalLodPolicy.shouldCollapse(
      branchLength: node.branchLength,
      zoomScale: zoomScale,
      hasChildren: node.hasChildren,
    );

    if (collapsed) {
      _paintLeafBlob(canvas, node);
      return;
    }

    _paintBranch(canvas, node);

    if (FractalLodPolicy.shouldShowLabel(
      branchLength: node.branchLength,
      zoomScale: zoomScale,
    )) {
      _paintLabel(canvas, node);
    } else if (node.isGenus) {
      _paintGenusDot(canvas, node);
    }

    _paintSubtree(canvas, node, parentExpanded: true);
  }

  void _paintBranch(Canvas canvas, FractalLayoutNode node) {
    final path = node.branchPath;
    if (path == null) return;

    final ratio = node.strokeWidth / layout.maxStrokeWidth;
    final paint = Paint()
      ..color = branchColor.withValues(alpha: 0.3 + 0.6 * ratio)
      ..strokeWidth = node.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  void _paintLeafBlob(Canvas canvas, FractalLayoutNode node) {
    final radius = FractalLodPolicy.leafBlobRadius(
      leafCount: node.treeNode.leafCount,
      branchLength: node.branchLength,
      zoomScale: zoomScale,
      maxLeaves: layout.root.treeNode.leafCount,
    );

    final paint = Paint()
      ..color = leafColor.withValues(
        alpha: node.isGenus ? 0.95 : 0.75,
      );
    canvas.drawCircle(node.position, radius, paint);

    if (node.isGenus &&
        FractalLodPolicy.shouldShowLabel(
          branchLength: node.branchLength,
          zoomScale: zoomScale,
        )) {
      _paintLabel(canvas, node, isGenus: true);
    }
  }

  void _paintGenusDot(Canvas canvas, FractalLayoutNode node) {
    final paint = Paint()..color = leafColor;
    canvas.drawCircle(node.position, 3.5, paint);
  }

  void _paintLabel(
    Canvas canvas,
    FractalLayoutNode node, {
    bool isGenus = false,
  }) {
    final isGenusNode = isGenus || node.isGenus;
    final fontSize = isGenusNode ? 10.5 : (node.depth <= 2 ? 12.0 : 9.5);
    final color = isGenusNode ? labelColor : labelMutedColor;
    final fontWeight =
        node.depth <= 1 ? FontWeight.w700 : FontWeight.w500;

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
    )..layout(maxWidth: 100);

    final angle = _labelAngle(node);
    final offset = Offset(
      node.position.dx - textPainter.width / 2,
      node.position.dy - 16 - (isGenusNode ? 4 : 0),
    );

    if (angle.abs() > 0.01) {
      canvas.save();
      canvas.translate(node.position.dx, node.position.dy);
      canvas.rotate(angle * 0.15);
      canvas.translate(-node.position.dx, -node.position.dy);
      textPainter.paint(canvas, offset);
      canvas.restore();
    } else {
      textPainter.paint(canvas, offset);
    }
  }

  double _labelAngle(FractalLayoutNode node) {
    final parent = node.parentPosition;
    if (parent == null) return 0;
    return math.atan2(node.position.dx - parent.dx, parent.dy - node.position.dy);
  }

  @override
  bool shouldRepaint(covariant FractalFernPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        (oldDelegate.zoomScale - zoomScale).abs() > 0.02 ||
        oldDelegate.branchColor != branchColor ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.labelMutedColor != labelMutedColor ||
        oldDelegate.rootGlowColor != rootGlowColor ||
        oldDelegate.leafColor != leafColor;
  }
}

/// Fits the fractal tree in [viewportSize] with root near the bottom.
Matrix4 fitFractalTransform({
  required Rect bounds,
  required Size viewportSize,
  double bottomPadding = 56,
}) {
  if (bounds.isEmpty || viewportSize.isEmpty) return Matrix4.identity();

  final contentWidth = bounds.width;
  final contentHeight = bounds.height;
  final scaleX = viewportSize.width / contentWidth;
  final scaleY = (viewportSize.height - bottomPadding) / contentHeight;
  final scale = math.min(scaleX, scaleY).clamp(0.01, 2.0);

  final treeCenterX = contentWidth / 2;
  final treeBottom = contentHeight;
  final viewCenterX = viewportSize.width / 2;
  final viewBottom = viewportSize.height - bottomPadding;

  final tx = viewCenterX - treeCenterX * scale;
  final ty = viewBottom - treeBottom * scale;

  return Matrix4.identity()
    ..setEntry(0, 0, scale)
    ..setEntry(1, 1, scale)
    ..setEntry(0, 3, tx)
    ..setEntry(1, 3, ty);
}
