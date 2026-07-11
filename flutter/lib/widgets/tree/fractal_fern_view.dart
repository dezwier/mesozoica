import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
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
    final scale = _transformController.value.getMaxScaleOnAxis();
    if ((scale - _zoomScale).abs() > 0.02) {
      setState(() => _zoomScale = scale);
    }
  }

  void _applyInitialTransform(Size viewportSize) {
    if (_initialTransformApplied || widget.layout.bounds.isEmpty) return;
    _initialTransformApplied = true;

    _transformController.value = fitFractalTransform(
      bounds: widget.layout.bounds,
      viewportSize: viewportSize,
    );
    _zoomScale = _transformController.value.getMaxScaleOnAxis();
  }

  Offset _toTreeCoordinates(Offset localPosition) {
    final matrix = Matrix4.inverted(_transformController.value);
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
      if (!FractalLodPolicy.isGenusTappable(
        branchLength: node.branchLength,
        zoomScale: _zoomScale,
        isGenus: node.isGenus,
      )) {
        continue;
      }

      final distance = (node.position - treePoint).distance;
      final hitRadius = math.max(
        12,
        FractalLodPolicy.leafBlobRadius(
          leafCount: node.treeNode.leafCount,
          branchLength: node.branchLength,
          zoomScale: _zoomScale,
          maxLeaves: widget.layout.root.treeNode.leafCount,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
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
                    branchColor: cardTheme.cardAccent,
                    labelColor: cardTheme.cardTextPrimary,
                    labelMutedColor: cardTheme.cardTextMuted,
                    rootGlowColor: scheme.primary,
                    leafColor: cardTheme.cardAccent,
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
