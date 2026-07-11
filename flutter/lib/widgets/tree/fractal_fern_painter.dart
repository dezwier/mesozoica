import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/fractal_label_placer.dart';
import '../../services/fractal_tree_layout.dart';

class FractalFernPainter extends CustomPainter {
  FractalFernPainter({
    required this.layout,
    required this.viewTransform,
    required this.zoomScale,
    required this.visibleTreeRect,
    required this.viewportCenterTree,
    required this.branchColor,
    required this.labelColor,
    required this.labelMutedColor,
    required this.rootGlowColor,
    required this.leafColor,
    required this.genusLeafColor,
  });

  final FractalTreeLayout layout;
  final Matrix4 viewTransform;
  final double zoomScale;
  final Rect visibleTreeRect;
  final Offset viewportCenterTree;
  final Color branchColor;
  final Color labelColor;
  final Color labelMutedColor;
  final Color rootGlowColor;
  final Color leafColor;
  final Color genusLeafColor;

  static const _labelPlacer = FractalLabelPlacer();

  static const _genusDotScreenRadius = 5.5;
  static const _rootGlowScreenRadius = 56.0;

  double _treeUnits(double screenPixels) =>
      FractalLodPolicy.treeUnitsWithBoost(
        screenPixels: screenPixels,
        zoomScale: zoomScale,
      );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.transform(viewTransform.storage);
    canvas.translate(-layout.bounds.left, -layout.bounds.top);

    _paintRootGlow(canvas, layout.root);

    _paintBranches(canvas, layout.root);

    _paintDynamicLabels(canvas);
    canvas.restore();
  }

  void _paintRootGlow(Canvas canvas, FractalLayoutNode root) {
    if (!visibleTreeRect.inflate(80).contains(root.position)) return;

    final glowRadius = _treeUnits(_rootGlowScreenRadius + layout.maxStrokeWidth);
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
  }

  void _paintBranches(Canvas canvas, FractalLayoutNode node) {
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
      if (_isNearVisible(node.position)) {
        _paintLeafBlob(canvas, node);
      }
      return;
    }

    if (_branchIntersectsVisible(node)) {
      _paintBranch(canvas, node);
    }

    if (node.isGenus && _isNearVisible(node.position)) {
      _paintGenusDot(canvas, node);
    }

    _paintBranches(canvas, node);
  }

  bool _isNearVisible(Offset position) {
    return visibleTreeRect.inflate(40).contains(position);
  }

  bool _branchIntersectsVisible(FractalLayoutNode node) {
    if (node.parentPosition == null) return true;
    final parent = node.parentPosition!;
    final clip = visibleTreeRect.inflate(24);
    if (clip.contains(node.position) || clip.contains(parent)) return true;
    return clip.intersect(
      Rect.fromPoints(parent, node.position),
    ).isEmpty == false;
  }

  void _paintBranch(Canvas canvas, FractalLayoutNode node) {
    final path = node.branchPath;
    if (path == null) return;

    final ratio = node.strokeWidth / layout.maxStrokeWidth;
    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high
      ..color = branchColor.withValues(alpha: 0.3 + 0.6 * ratio)
      ..strokeWidth = _treeUnits(node.strokeWidth)
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
      isGenus: node.isGenus,
    );

    final paint = Paint()
      ..color = (node.isGenus ? genusLeafColor : leafColor).withValues(
        alpha: node.isGenus ? 1 : 0.75,
      );
    canvas.drawCircle(node.position, radius, paint);
  }

  void _paintGenusDot(Canvas canvas, FractalLayoutNode node) {
    final radius = _treeUnits(_genusDotScreenRadius);
    final ringWidth = _treeUnits(1.5);
    final paint = Paint()..color = genusLeafColor;
    canvas.drawCircle(node.position, radius, paint);
    canvas.drawCircle(
      node.position,
      radius,
      Paint()
        ..color = genusLeafColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth,
    );
  }

  void _paintDynamicLabels(Canvas canvas) {
    if (visibleTreeRect.isEmpty) return;

    final genusStyle = TextStyle(
      color: genusLeafColor,
      fontSize: FractalLabelPlacer.genusScreenFontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    );
    final shallowCladeStyle = TextStyle(
      color: labelColor,
      fontSize: FractalLabelPlacer.shallowCladeScreenFontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    );
    final cladeStyle = TextStyle(
      color: labelMutedColor,
      fontSize: FractalLabelPlacer.cladeScreenFontSize,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    );

    final candidates = _labelPlacer.collectCandidates(
      root: layout.root,
      visibleTreeRect: visibleTreeRect,
      viewportCenterTree: viewportCenterTree,
      zoomScale: zoomScale,
      genusStyle: genusStyle,
      cladeStyle: cladeStyle,
      shallowCladeStyle: shallowCladeStyle,
    );

    final placed = _labelPlacer.placeWithoutOverlap(
      candidates,
      zoomScale: zoomScale,
    );
    for (final label in placed) {
      _paintCrispLabel(
        canvas,
        label.candidate.textPainter,
        label.candidate.anchor,
        label.screenOffset,
      );
    }
  }

  /// Paints text at native screen resolution — immune to zoom blur.
  void _paintCrispLabel(
    Canvas canvas,
    TextPainter textPainter,
    Offset anchor,
    Offset screenOffset,
  ) {
    if (zoomScale <= 0) return;
    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.scale(1 / zoomScale, 1 / zoomScale);
    textPainter.paint(canvas, screenOffset);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FractalFernPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.viewTransform != viewTransform ||
        (oldDelegate.zoomScale - zoomScale).abs() > 0.001 ||
        oldDelegate.visibleTreeRect != visibleTreeRect ||
        (oldDelegate.viewportCenterTree - viewportCenterTree).distance > 0.5 ||
        oldDelegate.branchColor != branchColor ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.labelMutedColor != labelMutedColor ||
        oldDelegate.rootGlowColor != rootGlowColor ||
        oldDelegate.leafColor != leafColor ||
        oldDelegate.genusLeafColor != genusLeafColor;
  }
}

/// Fits the fractal tree in [viewportSize], centered.
Matrix4 fitFractalTransform({
  required Rect bounds,
  required Size viewportSize,
  double viewportPadding = 48,
}) {
  if (bounds.isEmpty || viewportSize.isEmpty) return Matrix4.identity();

  final contentWidth = bounds.width;
  final contentHeight = bounds.height;
  final scaleX = (viewportSize.width - viewportPadding * 2) / contentWidth;
  final scaleY = (viewportSize.height - viewportPadding * 2) / contentHeight;
  final scale = math.min(scaleX, scaleY).clamp(0.01, 2.0);

  final tx = (viewportSize.width - contentWidth * scale) / 2;
  final ty = (viewportSize.height - contentHeight * scale) / 2;

  return Matrix4.identity()
    ..setEntry(0, 0, scale)
    ..setEntry(1, 1, scale)
    ..setEntry(0, 3, tx)
    ..setEntry(1, 3, ty);
}
