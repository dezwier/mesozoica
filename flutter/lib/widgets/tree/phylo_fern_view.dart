import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../services/phylo_tree_layout.dart';
import '../../services/phylo_zoom_policy.dart';
import '../../theme/dino_card_theme.dart';
import 'phylo_fern_painter.dart';

class PhyloFernView extends StatefulWidget {
  const PhyloFernView({
    super.key,
    required this.layout,
    this.onGenusTap,
  });

  final PhyloTreeLayout layout;
  final ValueChanged<DinosaurSummary>? onGenusTap;

  @override
  State<PhyloFernView> createState() => _PhyloFernViewState();
}

class _PhyloFernViewState extends State<PhyloFernView>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController =
      TransformationController();
  bool _initialTransformApplied = false;
  double _zoomScale = 1.0;
  PhyloDetailLevel _detailLevel = PhyloDetailLevel.macro;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void didUpdateWidget(covariant PhyloFernView oldWidget) {
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
    final level = PhyloZoomPolicy.detailLevel(scale);
    if ((scale - _zoomScale).abs() > 0.02 || level != _detailLevel) {
      setState(() {
        _zoomScale = scale;
        _detailLevel = level;
      });
    }
  }

  void _applyInitialTransform(Size viewportSize) {
    if (_initialTransformApplied) return;
    _initialTransformApplied = true;

    final macroBounds = widget.layout.boundsForMaxDepth(
      PhyloZoomPolicy.initialMaxDepth,
    );
    final matrix = fitTreeTransform(
      bounds: macroBounds,
      layoutBounds: widget.layout.bounds,
      viewportSize: viewportSize,
    );
    _transformController.value = matrix;
    _zoomScale = matrix.getMaxScaleOnAxis();
    _detailLevel = PhyloZoomPolicy.detailLevel(_zoomScale);
  }

  Offset _toTreeCoordinates(Offset localPosition) {
    final matrix = Matrix4.inverted(_transformController.value);
    final transformed = MatrixUtils.transformPoint(matrix, localPosition);
    return Offset(
      transformed.dx + widget.layout.bounds.left,
      transformed.dy + widget.layout.bounds.top,
    );
  }

  void _handleTapUp(TapUpDetails details, Size viewportSize) {
    final treePoint = _toTreeCoordinates(details.localPosition);
    PhyloLayoutNode? hit;

    for (final node in widget.layout.nodes.reversed) {
      if (!PhyloZoomPolicy.isNodeVisible(node, _zoomScale)) continue;
      if (!node.hitTarget.contains(treePoint)) continue;
      hit = node;
      break;
    }

    if (hit == null) return;

    if (hit.isGenus && hit.treeNode.dinosaurs.isNotEmpty) {
      _animateToNode(
        hit,
        viewportSize,
        onComplete: () {
          widget.onGenusTap?.call(hit!.treeNode.dinosaurs.first);
        },
      );
      return;
    }

    if (PhyloZoomPolicy.hasHiddenDescendants(hit, _zoomScale)) {
      final revealDepth = math.min(
        hit.treeNode.maxDescendantDepth,
        hit.depth + 2,
      );
      _animateToNode(
        hit,
        viewportSize,
        targetScale: PhyloZoomPolicy.minScaleForDepth(revealDepth + 1),
      );
      return;
    }

    _animateToNode(hit, viewportSize);
  }

  void _animateToNode(
    PhyloLayoutNode node,
    Size viewportSize, {
    VoidCallback? onComplete,
    double? targetScale,
  }) {
    final canvasTarget = Offset(
      node.position.dx - widget.layout.bounds.left,
      node.position.dy - widget.layout.bounds.top,
    );
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final resolvedScale = math
        .max(
          currentScale,
          targetScale ?? PhyloZoomPolicy.minScaleForDepth(node.depth + 1),
        )
        .clamp(0.05, 6.0);

    final endMatrix = Matrix4.identity()
      ..setEntry(0, 0, resolvedScale)
      ..setEntry(1, 1, resolvedScale)
      ..setEntry(
        0,
        3,
        viewportSize.width / 2 - canvasTarget.dx * resolvedScale,
      )
      ..setEntry(
        1,
        3,
        viewportSize.height / 2 - canvasTarget.dy * resolvedScale,
      );

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    final animation = Matrix4Tween(
      begin: _transformController.value,
      end: endMatrix,
    ).animate(CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    ));

    animation.addListener(() {
      _transformController.value = animation.value;
    });
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        onComplete?.call();
        controller.dispose();
      }
    });
    controller.forward();
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

        return Stack(
          children: [
            GestureDetector(
              onTapUp: (details) => _handleTapUp(details, viewportSize),
              child: InteractiveViewer(
                transformationController: _transformController,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(200),
                minScale: 0.05,
                maxScale: 6,
                child: RepaintBoundary(
                  child: SizedBox(
                    width: canvasSize.width,
                    height: canvasSize.height,
                    child: CustomPaint(
                      painter: PhyloFernPainter(
                        layout: widget.layout,
                        branchColor: cardTheme.cardAccent,
                        labelColor: cardTheme.cardTextPrimary,
                        labelMutedColor: cardTheme.cardTextMuted,
                        rootGlowColor: scheme.primary,
                        zoomScale: _zoomScale,
                      ),
                      size: canvasSize,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: _ZoomHintChip(detailLevel: _detailLevel),
            ),
          ],
        );
      },
    );
  }
}

class _ZoomHintChip extends StatelessWidget {
  const _ZoomHintChip({required this.detailLevel});

  final PhyloDetailLevel detailLevel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = switch (detailLevel) {
      PhyloDetailLevel.macro => 'Major clades · pinch or tap to explore',
      PhyloDetailLevel.meso => 'Subclades · zoom for families',
      PhyloDetailLevel.fine => 'Deep taxonomy · zoom for genera',
      PhyloDetailLevel.genus => 'Genus level',
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}
