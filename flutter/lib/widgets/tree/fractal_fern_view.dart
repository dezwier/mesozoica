import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../services/fractal_label_placer.dart';
import '../../services/fractal_tree_layout.dart';
import '../../theme/dino_card_theme.dart';
import 'fractal_fern_painter.dart';

class FractalFernView extends StatefulWidget {
  const FractalFernView({
    super.key,
    required this.layout,
    this.onGenusTap,
  });

  final FractalTreeLayout layout;
  final ValueChanged<DinosaurSummary>? onGenusTap;

  @override
  State<FractalFernView> createState() => _FractalFernViewState();
}

class _FractalFernViewState extends State<FractalFernView> {
  final TransformationController _transformController =
      TransformationController();

  bool _initialTransformApplied = false;
  double _zoomScale = 1.0;
  Matrix4 _transform = Matrix4.identity();
  Size _viewportSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void didUpdateWidget(covariant FractalFernView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout != widget.layout) {
      _initialTransformApplied = false;
    }
  }

  @override
  void dispose() {
    _transformController
      ..removeListener(_onTransformChanged)
      ..dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    setState(() {
      _transform = _transformController.value.clone();
      _zoomScale = _transform.getMaxScaleOnAxis();
    });
  }

  void _applyInitialTransform(Size viewportSize) {
    if (_initialTransformApplied || widget.layout.bounds.isEmpty) return;
    _initialTransformApplied = true;

    _transformController.value = fitFractalTransform(
      bounds: widget.layout.bounds,
      viewportSize: viewportSize,
    );
    _transform = _transformController.value.clone();
    _zoomScale = _transform.getMaxScaleOnAxis();
  }

  Rect get _visibleTreeRect {
    if (_viewportSize.isEmpty) return Rect.zero;
    return visibleTreeRect(
      viewportSize: _viewportSize,
      transform: _transform,
      layoutBounds: widget.layout.bounds,
    );
  }

  Offset get _viewportCenterTree {
    if (_viewportSize.isEmpty) return Offset.zero;
    return viewportCenterInTree(
      viewportSize: _viewportSize,
      transform: _transform,
      layoutBounds: widget.layout.bounds,
    );
  }

  Offset _toTreeCoordinates(Offset localPosition) {
    final matrix = Matrix4.inverted(_transform);
    final transformed = MatrixUtils.transformPoint(matrix, localPosition);
    return Offset(
      transformed.dx + widget.layout.bounds.left,
      transformed.dy + widget.layout.bounds.top,
    );
  }

  void _handleTapUp(TapUpDetails details) {
    final treePoint = _toTreeCoordinates(details.localPosition);
    FractalLayoutNode? best;
    var bestDistance = double.infinity;

    for (final node in widget.layout.genusNodes) {
      if (!_visibleTreeRect.inflate(24).contains(node.position)) continue;

      if (!FractalLodPolicy.isGenusTappable(
        branchLength: node.branchLength,
        zoomScale: _zoomScale,
        isGenus: node.isGenus,
      )) {
        continue;
      }

      final distance = (node.position - treePoint).distance;
      final hitRadius = math.max(
        FractalLodPolicy.treeUnits(12, _zoomScale),
        FractalLodPolicy.leafBlobRadius(
          leafCount: node.treeNode.leafCount,
          branchLength: node.branchLength,
          zoomScale: _zoomScale,
          maxLeaves: widget.layout.root.treeNode.leafCount,
          isGenus: true,
        ),
      );

      if (distance <= hitRadius && distance < bestDistance) {
        best = node;
        bestDistance = distance;
      }
    }

    if (best != null && best.treeNode.dinosaurs.isNotEmpty) {
      widget.onGenusTap?.call(best.treeNode.dinosaurs.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final bounds = widget.layout.bounds;
    final canvasSize = Size(bounds.width, bounds.height);

    final genusLeafColor = Color.lerp(
      cardTheme.cardAccent,
      const Color(0xFF3E2723),
      cardTheme.isLight ? 0.5 : 0.35,
    )!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        if (_viewportSize != viewportSize) {
          _viewportSize = viewportSize;
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _applyInitialTransform(viewportSize);
        });

        return GestureDetector(
          onTapUp: _handleTapUp,
          child: InteractiveViewer(
            transformationController: _transformController,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(240),
            minScale: 0.01,
            maxScale: 20,
            child: RepaintBoundary(
              child: SizedBox(
                width: canvasSize.width,
                height: canvasSize.height,
                child: CustomPaint(
                  painter: FractalFernPainter(
                    layout: widget.layout,
                    zoomScale: _zoomScale,
                    visibleTreeRect: _visibleTreeRect,
                    viewportCenterTree: _viewportCenterTree,
                    branchColor: cardTheme.cardAccent,
                    labelColor: cardTheme.cardTextPrimary,
                    labelMutedColor: cardTheme.cardTextMuted,
                    rootGlowColor: scheme.primary,
                    leafColor: cardTheme.cardAccent,
                    genusLeafColor: genusLeafColor,
                  ),
                  size: canvasSize,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
