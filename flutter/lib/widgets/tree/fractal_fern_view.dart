import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../services/fractal_label_placer.dart';
import '../../services/fractal_tree_layout.dart';
import '../../theme/dino_card_theme.dart';
import '../cards/dinosaur_turnable_card.dart';
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
  State<FractalFernView> createState() => FractalFernViewState();
}

class FractalFernViewState extends State<FractalFernView>
    with TickerProviderStateMixin {
  static const _labelPlacer = FractalLabelPlacer();
  static const _flyDuration = Duration(milliseconds: 1000);

  final TransformationController _transformController =
      TransformationController();

  AnimationController? _flyController;
  Matrix4 _flyStartTransform = Matrix4.identity();
  Matrix4? _flyTargetTransform;
  FractalLayoutNode? _flyTargetNode;

  bool _initialTransformApplied = false;
  double _zoomScale = 1.0;
  Matrix4 _transform = Matrix4.identity();
  Size _viewportSize = Size.zero;
  FractalLayoutNode? _tapRevealedNode;
  final Map<String, _TrackedGenusCard> _trackedCards = {};

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
      _tapRevealedNode = null;
      _trackedCards.clear();
    }
  }

  @override
  void dispose() {
    _flyController?.dispose();
    _transformController
      ..removeListener(_onTransformChanged)
      ..dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    setState(() {
      _transform = _transformController.value.clone();
      _zoomScale = _transform.getMaxScaleOnAxis();
      if (_flyController?.isAnimating != true) {
        _clearTapRevealedIfNeeded();
      }
      _syncTrackedCards(_displayedGenusCards().cards);
    });
  }

  bool _cardsNeedSync(List<PlacedGenusCard> desiredCards) {
    final desiredKeys = desiredCards.map(_genusCardKey).toSet();
    for (final key in desiredKeys) {
      final tracked = _trackedCards[key];
      if (tracked == null || tracked.isExiting) return true;
    }
    return false;
  }

  void _scheduleTrackedCardSyncIfNeeded(List<PlacedGenusCard> desiredCards) {
    if (_flyController?.isAnimating == true || _viewportSize.isEmpty) return;
    if (!_cardsNeedSync(desiredCards)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _flyController?.isAnimating == true) return;
      setState(() {
        _clearTapRevealedIfNeeded();
        _syncTrackedCards(_displayedGenusCards().cards);
      });
    });
  }

  void _markFadeInComplete(String key) {
    final tracked = _trackedCards[key];
    if (tracked == null || !tracked.needsFadeIn) return;
    setState(() {
      _trackedCards[key] = tracked.copyWith(needsFadeIn: false);
    });
  }

  void _cancelFlyAnimation({bool clearTarget = true}) {
    _flyController?.dispose();
    _flyController = null;
    _flyTargetTransform = null;
    if (clearTarget) {
      _flyTargetNode = null;
    }
  }

  bool _shouldKeepTapRevealedCard() {
    final node = _tapRevealedNode;
    if (node == null) return false;
    if (_flyController?.isAnimating == true || _flyTargetNode == node) {
      return true;
    }
    if (!FractalLodPolicy.shouldShowGenusCard(
      branchLength: node.branchLength,
      zoomScale: _zoomScale,
      isGenus: true,
    )) {
      return false;
    }
    return _isFocusedOnNode(node, FractalLodPolicy.genusCardFactsZoomScale());
  }

  void _clearTapRevealedIfNeeded() {
    if (_tapRevealedNode != null && !_shouldKeepTapRevealedCard()) {
      _tapRevealedNode = null;
    }
  }

  bool _shouldCenterCardOnScreen(FractalLayoutNode node) {
    return _tapRevealedNode == node && _shouldKeepTapRevealedCard();
  }

  bool _isFocusedOnNode(FractalLayoutNode node, double targetScale) {
    if (_viewportSize.isEmpty) return false;
    final screen = _treeToScreen(node.position, widget.layout.bounds);
    final center = Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    return _zoomScale >= targetScale - 0.25 &&
        (screen - center).distance < 56;
  }

  void _revealFlyTargetCard() {
    final target = _flyTargetNode;
    if (target == null) return;
    setState(() {
      _tapRevealedNode = target;
      _flyTargetNode = null;
      _flyTargetTransform = null;
      _syncTrackedCards(_displayedGenusCards().cards);
    });
  }

  void _beginTapFly(FractalLayoutNode node) {
    setState(() {
      _tapRevealedNode = node;
      _syncTrackedCards(_displayedGenusCards().cards);
    });
  }

  void _flyToGenusNode(FractalLayoutNode node) {
    if (_viewportSize.isEmpty || widget.layout.bounds.isEmpty) return;

    final bounds = widget.layout.bounds;
    final targetScale = FractalLodPolicy.genusCardFactsZoomScale();
    final targetTransform = focusFractalTransform(
      treePoint: node.position,
      bounds: bounds,
      viewportSize: _viewportSize,
      scale: targetScale,
    );

    _beginTapFly(node);

    if (_isFocusedOnNode(node, targetScale)) {
      _cancelFlyAnimation();
      _flyTargetNode = node;
      _transformController.value = targetTransform;
      _revealFlyTargetCard();
      return;
    }

    _cancelFlyAnimation(clearTarget: false);
    _flyTargetNode = node;
    _flyStartTransform = _transformController.value.clone();
    _flyTargetTransform = targetTransform;

    _flyController = AnimationController(vsync: this, duration: _flyDuration)
      ..addListener(() {
        if (!mounted || _flyController == null) return;
        final t = Curves.easeInOutCubic.transform(_flyController!.value);
        _transformController.value = lerpFractalFocusTransform(
          start: _flyStartTransform,
          endTreePoint: node.position,
          bounds: bounds,
          viewportSize: _viewportSize,
          endScale: targetScale,
          t: t,
        );
      })
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed || !mounted) return;
        final snap = _flyTargetTransform;
        if (snap != null) {
          _transformController.value = snap.clone();
        }
        _flyController?.dispose();
        _flyController = null;
        _revealFlyTargetCard();
      })
      ..forward();
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

  /// Animates pan/zoom back to the initial fit view and dismisses fly-to cards.
  void resetView() {
    if (_viewportSize.isEmpty || widget.layout.bounds.isEmpty) return;

    final fitTransform = fitFractalTransform(
      bounds: widget.layout.bounds,
      viewportSize: _viewportSize,
    );

    _cancelFlyAnimation();
    setState(() {
      _tapRevealedNode = null;
    });

    _flyStartTransform = _transformController.value.clone();
    _flyTargetTransform = fitTransform;

    _flyController = AnimationController(vsync: this, duration: _flyDuration)
      ..addListener(() {
        if (!mounted || _flyController == null) return;
        final t = Curves.easeInOutCubic.transform(_flyController!.value);
        _transformController.value = lerpFractalFocusTransform(
          start: _flyStartTransform,
          endTreePoint: widget.layout.bounds.center,
          bounds: widget.layout.bounds,
          viewportSize: _viewportSize,
          endScale: fitTransform.getMaxScaleOnAxis(),
          t: t,
        );
      })
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed || !mounted) return;
        _transformController.value = fitTransform.clone();
        _flyController?.dispose();
        _flyController = null;
        _flyTargetTransform = null;
        setState(() => _syncTrackedCards(_displayedGenusCards().cards));
      })
      ..forward();
  }

  Rect get _visibleTreeRect {
    if (_viewportSize.isEmpty) return Rect.zero;
    return visibleTreeRect(
      viewportSize: _viewportSize,
      transform: _transform,
      layoutBounds: widget.layout.bounds,
    );
  }

  Offset _toTreeCoordinates(Offset viewportPoint) {
    final scene = _transformController.toScene(viewportPoint);
    return Offset(
      scene.dx + widget.layout.bounds.left,
      scene.dy + widget.layout.bounds.top,
    );
  }

  Offset _treeToScreen(Offset treePoint, Rect bounds) {
    final local = Offset(
      treePoint.dx - bounds.left,
      treePoint.dy - bounds.top,
    );
    return MatrixUtils.transformPoint(_transform, local);
  }

  ({
    List<PlacedGenusCard> cards,
    Set<FractalLayoutNode> cardNodes,
    List<Rect> cardTreeRects,
  }) _layoutGenusCards() {
    final cardCandidates = _labelPlacer.collectGenusCardCandidates(
      root: widget.layout.root,
      visibleTreeRect: _visibleTreeRect,
      zoomScale: _zoomScale,
      viewportWidth: _viewportSize.width,
    );
    final placedCards = _labelPlacer.placeGenusCardsWithoutOverlap(
      cardCandidates,
      zoomScale: _zoomScale,
    );
    return (
      cards: placedCards,
      cardNodes: _labelPlacer.genusCardNodes(placedCards),
      cardTreeRects: placedCards
          .map((card) => card.treeRect(_zoomScale))
          .toList(growable: false),
    );
  }

  ({
    List<PlacedGenusCard> cards,
    Set<FractalLayoutNode> cardNodes,
    List<Rect> cardTreeRects,
  }) _displayedGenusCards() {
    final zoomCards = _layoutGenusCards();
    final tapNode = _tapRevealedNode;
    if (tapNode == null ||
        tapNode.treeNode.dinosaurs.isEmpty ||
        !_shouldKeepTapRevealedCard()) {
      return zoomCards;
    }

    if (zoomCards.cardNodes.contains(tapNode)) {
      return zoomCards;
    }

    final tapCard = _labelPlacer.placedGenusCardForNode(
      node: tapNode,
      dinosaur: tapNode.treeNode.dinosaurs.first,
      viewportWidth: _viewportSize.width,
      zoomScale: _zoomScale,
    );
    final cards = [...zoomCards.cards, tapCard];
    return (
      cards: cards,
      cardNodes: {...zoomCards.cardNodes, tapNode},
      cardTreeRects: cards
          .map((card) => card.treeRect(_zoomScale))
          .toList(growable: false),
    );
  }

  String _genusCardKey(PlacedGenusCard card) {
    final anchor = card.candidate.anchor;
    return '${card.candidate.node.label}@'
        '${anchor.dx.toStringAsFixed(1)},${anchor.dy.toStringAsFixed(1)}';
  }

  void _syncTrackedCards(List<PlacedGenusCard> desiredCards) {
    final desiredByKey = {
      for (final card in desiredCards) _genusCardKey(card): card,
    };
    final next = <String, _TrackedGenusCard>{};

    for (final entry in _trackedCards.entries) {
      final desired = desiredByKey[entry.key];
      if (desired != null) {
        final node = desired.candidate.node;
        final wasExiting = entry.value.isExiting;
        next[entry.key] = entry.value.copyWith(
          card: desired,
          isExiting: false,
          needsFadeIn: wasExiting || entry.value.needsFadeIn,
          centerOnScreen: _shouldCenterCardOnScreen(node),
        );
      } else if (!entry.value.isExiting) {
        next[entry.key] = entry.value.copyWith(isExiting: true);
      } else {
        next[entry.key] = entry.value;
      }
    }

    for (final entry in desiredByKey.entries) {
      next.putIfAbsent(
        entry.key,
        () => _TrackedGenusCard(
          key: entry.key,
          card: entry.value,
          needsFadeIn: true,
          centerOnScreen: _shouldCenterCardOnScreen(entry.value.candidate.node),
        ),
      );
    }

    _trackedCards
      ..clear()
      ..addAll(next);
  }

  void _removeTrackedCard(String key) {
    setState(() => _trackedCards.remove(key));
  }

  ({
    List<PlacedGenusCard> cards,
    Set<FractalLayoutNode> cardNodes,
    List<Rect> cardTreeRects,
  }) _cardPaintState(double zoomScale) {
    final cards = _trackedCards.values
        .map((tracked) => tracked.card)
        .toList(growable: false);
    return (
      cards: cards,
      cardNodes: _labelPlacer.genusCardNodes(cards),
      cardTreeRects: cards
          .map((card) => card.treeRect(zoomScale))
          .toList(growable: false),
    );
  }

  double _genusTapHitRadius(FractalLayoutNode node) {
    final labelPad =
        FractalLabelPlacer.genusScreenFontSizeFor(_zoomScale) * 2.5;
    return math.max(
      labelPad,
      math.max(
        FractalLodPolicy.treeUnits(20, _zoomScale),
        FractalLodPolicy.leafBlobRadius(
          leafCount: node.treeNode.leafCount,
          branchLength: node.branchLength,
          zoomScale: _zoomScale,
          maxLeaves: widget.layout.root.treeNode.leafCount,
          isGenus: true,
        ),
      ),
    );
  }

  bool _isGenusNodeTappable(FractalLayoutNode node) {
    if (!node.isGenus || node.treeNode.dinosaurs.isEmpty) return false;
    if (!_visibleTreeRect.inflate(48).contains(node.position)) return false;

    return !FractalLodPolicy.shouldCollapse(
      branchLength: node.branchLength,
      zoomScale: _zoomScale,
      hasChildren: node.hasChildren,
    );
  }

  void _handleTapUp(TapUpDetails details) {
    final treePoint = _toTreeCoordinates(details.localPosition);
    FractalLayoutNode? best;
    var bestDistance = double.infinity;

    for (final node in widget.layout.genusNodes) {
      if (!_isGenusNodeTappable(node)) continue;

      final distance = (node.position - treePoint).distance;
      final hitRadius = _genusTapHitRadius(node);

      if (distance <= hitRadius && distance < bestDistance) {
        best = node;
        bestDistance = distance;
      }
    }

    if (best != null) {
      widget.onGenusTap?.call(best.treeNode.dinosaurs.first);
      _flyToGenusNode(best);
    } else {
      _cancelFlyAnimation();
      setState(() {
        _tapRevealedNode = null;
        _syncTrackedCards(_displayedGenusCards().cards);
      });
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

    final cladeLabelColor = cardTheme.isLight
        ? const Color.fromARGB(255, 103, 103, 103)
        : cardTheme.cardTextPrimary;

    final genusCards = _displayedGenusCards();
    _scheduleTrackedCardSyncIfNeeded(genusCards.cards);
    final cardPaint = _cardPaintState(_zoomScale);

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
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: FractalFernPainter(
                    layout: widget.layout,
                    viewTransform: _transform,
                    zoomScale: _zoomScale,
                    visibleTreeRect: _visibleTreeRect,
                    branchColor: cardTheme.cardAccent,
                    labelColor: cladeLabelColor,
                    labelMutedColor: cardTheme.cardTextMuted,
                    rootGlowColor: scheme.primary,
                    leafColor: cardTheme.cardAccent,
                    genusLeafColor: genusLeafColor,
                    genusCardNodes: cardPaint.cardNodes,
                    genusCardTreeRects: cardPaint.cardTreeRects,
                  ),
                ),
              ),
              Positioned.fill(
                child: InteractiveViewer(
                  transformationController: _transformController,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  minScale: 0.005,
                  maxScale: 200,
                  child: SizedBox(
                    width: canvasSize.width,
                    height: canvasSize.height,
                  ),
                ),
              ),
              for (final tracked in _trackedCards.values)
                _FadingInlineGenusCardLayer(
                  key: ValueKey(tracked.key),
                  card: tracked.card,
                  visible: !tracked.isExiting,
                  needsFadeIn: tracked.needsFadeIn,
                  zoomScale: _zoomScale,
                  centerOnScreen: tracked.centerOnScreen,
                  viewportSize: _viewportSize,
                  treeToScreen: (point) => _treeToScreen(point, bounds),
                  onFadeInComplete: () => _markFadeInComplete(tracked.key),
                  onDismissed: () => _removeTrackedCard(tracked.key),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TrackedGenusCard {
  const _TrackedGenusCard({
    required this.key,
    required this.card,
    this.isExiting = false,
    this.needsFadeIn = false,
    this.centerOnScreen = false,
  });

  final String key;
  final PlacedGenusCard card;
  final bool isExiting;
  final bool needsFadeIn;
  final bool centerOnScreen;

  _TrackedGenusCard copyWith({
    PlacedGenusCard? card,
    bool? isExiting,
    bool? needsFadeIn,
    bool? centerOnScreen,
  }) {
    return _TrackedGenusCard(
      key: key,
      card: card ?? this.card,
      isExiting: isExiting ?? this.isExiting,
      needsFadeIn: needsFadeIn ?? this.needsFadeIn,
      centerOnScreen: centerOnScreen ?? this.centerOnScreen,
    );
  }
}

class _FadingInlineGenusCardLayer extends StatefulWidget {
  const _FadingInlineGenusCardLayer({
    super.key,
    required this.card,
    required this.visible,
    required this.needsFadeIn,
    required this.zoomScale,
    required this.centerOnScreen,
    required this.viewportSize,
    required this.treeToScreen,
    required this.onFadeInComplete,
    required this.onDismissed,
  });

  final PlacedGenusCard card;
  final bool visible;
  final bool needsFadeIn;
  final double zoomScale;
  final bool centerOnScreen;
  final Size viewportSize;
  final Offset Function(Offset treePoint) treeToScreen;
  final VoidCallback onFadeInComplete;
  final VoidCallback onDismissed;

  @override
  State<_FadingInlineGenusCardLayer> createState() =>
      _FadingInlineGenusCardLayerState();
}

class _FadingInlineGenusCardLayerState extends State<_FadingInlineGenusCardLayer>
    with SingleTickerProviderStateMixin {
  static const _fadeDuration = Duration(milliseconds: 350);

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  bool _dismissPending = false;
  bool _fadeInCompleteNotified = false;

  void _startFadeIn() {
    _dismissPending = false;
    _fadeController.value = 0;
    _fadeController.forward().whenComplete(() {
      if (!mounted || !widget.visible) return;
      if (!_fadeInCompleteNotified && widget.needsFadeIn) {
        _fadeInCompleteNotified = true;
        widget.onFadeInComplete();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: _fadeDuration);
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    if (!widget.visible) {
      _fadeController.value = 0;
    } else if (widget.needsFadeIn) {
      _startFadeIn();
    } else {
      _fadeController.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _FadingInlineGenusCardLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      if (widget.needsFadeIn) {
        _fadeInCompleteNotified = false;
        _startFadeIn();
      } else {
        _dismissPending = false;
        _fadeController.value = 1;
      }
    } else if (!widget.visible && oldWidget.visible) {
      _startDismiss();
    }
  }

  void _startDismiss() {
    if (_dismissPending) return;
    _dismissPending = true;
    _fadeController.reverse().whenComplete(() {
      if (!mounted) return;
      widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anchor = widget.card.candidate.anchor;
    final size = FractalLodPolicy.genusCardScreenSize(
      widget.viewportSize.width,
      widget.zoomScale,
    );
    final halfW = size.width / 2;
    final halfH = size.height / 2;
    final left = widget.centerOnScreen
        ? (widget.viewportSize.width - size.width) / 2
        : widget.treeToScreen(anchor).dx - halfW;
    final top = widget.centerOnScreen
        ? (widget.viewportSize.height - size.height) / 2
        : widget.treeToScreen(anchor).dy - halfH;

    final showFacts = FractalLodPolicy.genusCardShowsFacts(widget.zoomScale);

    return Positioned(
      left: left,
      top: top,
      width: size.width,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: DinosaurTurnableCard(
          dinosaur: widget.card.candidate.dinosaur,
          showFrontFacts: showFacts,
          showArticleButton: showFacts,
          turnable: showFacts,
          titleFontSize:
              FractalLodPolicy.genusCardTitleFontSize(widget.zoomScale),
          subtitleFontSize:
              FractalLodPolicy.genusCardSubtitleFontSize(widget.zoomScale),
          overlayHeightFactor: FractalLodPolicy.genusCardFrontOverlayHeightFactor(
            widget.zoomScale,
          ),
        ),
      ),
    );
  }
}
