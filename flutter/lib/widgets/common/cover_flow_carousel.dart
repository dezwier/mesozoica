import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Apple-style Cover Flow: horizontal snap paging with Y-rotation, scale,
/// overlap, and back-to-front paint order. Gestures: horizontal drag pages;
/// taps fall through to the focused child (e.g. card flip).
///
/// Layout: lower indices sit to the left of focus, higher to the right.
/// Finger swipe left→right moves the deck left→right (toward earlier items).
///
/// Transforms tick via [AnimatedBuilder] on the [PageController] so card
/// subtrees are not rebuilt (or remounted) every scroll frame — that was
/// re-triggering [CachedNetworkImage] fade-ins.
class CoverFlowCarousel extends StatefulWidget {
  const CoverFlowCarousel({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.onPageChanged,
    this.viewportFraction = 0.68,
    this.padEnds = true,
    /// Vertical alignment of the deck in the viewport (-1 top, 0 center, 1 bottom).
    this.alignment = const Alignment(0, -0.18),
  });

  final int itemCount;

  /// [isFocused] is true only for the rounded current page.
  final Widget Function(BuildContext context, int index, bool isFocused)
      itemBuilder;

  final ValueChanged<int>? onPageChanged;
  final double viewportFraction;
  final bool padEnds;
  final Alignment alignment;

  @override
  State<CoverFlowCarousel> createState() => CoverFlowCarouselState();
}

class CoverFlowCarouselState extends State<CoverFlowCarousel> {
  late PageController _controller;
  int _reportedPage = 0;

  static const double _maxRotateY = 0.95;
  static const double _sideScale = 0.86;
  /// Fraction of card width between neighbors (positive = higher index to right).
  static const double _spacingFactor = 0.42;
  static const double _sideDim = 0.82;
  static const int _visibleRadius = 2;
  /// px/s — beyond this, fling advances at least one page.
  static const double _flingVelocityThreshold = 400;
  /// px/s per extra page on a strong fling.
  static const double _flingVelocityPerPage = 900;
  static const int _maxFlingPages = 4;

  PageController get controller => _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: widget.viewportFraction);
    _controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant CoverFlowCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewportFraction != widget.viewportFraction) {
      final page = _controller.hasClients
          ? (_controller.page ?? _reportedPage.toDouble())
          : _reportedPage.toDouble();
      _controller.dispose();
      _controller = PageController(
        viewportFraction: widget.viewportFraction,
        initialPage: page.round().clamp(0, math.max(0, widget.itemCount - 1)),
      );
      _controller.addListener(_onScroll);
    }
    if (widget.itemCount > 0 && _reportedPage >= widget.itemCount) {
      final clamped = widget.itemCount - 1;
      _reportedPage = clamped;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        _controller.jumpToPage(clamped);
      });
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients || !_controller.position.haveDimensions) {
      return;
    }
    final page = _controller.page ?? _reportedPage.toDouble();
    final rounded =
        page.round().clamp(0, math.max(0, widget.itemCount - 1)).toInt();
    // Only setState when the focused index changes — fractional scrolling is
    // handled by AnimatedBuilder without rebuilding card subtrees.
    if (rounded != _reportedPage) {
      setState(() => _reportedPage = rounded);
      widget.onPageChanged?.call(rounded);
    }
  }

  void animateToFirst({
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeOut,
  }) {
    if (!_controller.hasClients || widget.itemCount == 0) return;
    _controller.animateToPage(0, duration: duration, curve: curve);
  }

  void jumpToFirst() {
    if (!_controller.hasClients || widget.itemCount == 0) return;
    _controller.jumpToPage(0);
  }

  void animateToPage(
    int page, {
    Duration duration = const Duration(milliseconds: 320),
    Curve curve = Curves.easeOutCubic,
  }) {
    if (!_controller.hasClients || widget.itemCount == 0) return;
    final target = page.clamp(0, widget.itemCount - 1);
    _controller.animateToPage(target, duration: duration, curve: curve);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    // Finger right (dx > 0) → earlier pages → pixels decrease → deck moves right.
    final next = (position.pixels - details.delta.dx)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    position.jumpTo(next);
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_controller.hasClients || widget.itemCount == 0) return;
    final page = _controller.page ?? _reportedPage.toDouble();
    final vx = details.velocity.pixelsPerSecond.dx;
    final target = _targetPageForFling(page: page, velocityDx: vx);
    animateToPage(target);
  }

  /// Maps fling velocity to a page index. Stronger swipes skip multiple cards.
  /// Finger left (vx < 0) → later pages; finger right → earlier pages.
  int _targetPageForFling({
    required double page,
    required double velocityDx,
  }) {
    final maxIndex = widget.itemCount - 1;
    if (velocityDx.abs() < _flingVelocityThreshold) {
      return page.round().clamp(0, maxIndex);
    }
    final direction = velocityDx < 0 ? 1 : -1;
    final steps = (velocityDx.abs() / _flingVelocityPerPage)
        .round()
        .clamp(1, _maxFlingPages);
    return (page.round() + direction * steps).clamp(0, maxIndex);
  }

  Matrix4 _transformForDelta(double delta, double cardWidth) {
    final clamped = delta.clamp(-2.5, 2.5);
    final abs = clamped.abs();
    // Higher index (delta > 0) → right of focus, yaw so left edge comes forward.
    final rotateY = clamped.clamp(-1.0, 1.0) * _maxRotateY;
    final scale = 1.0 - (1.0 - _sideScale) * abs.clamp(0.0, 1.0);
    final translateX = clamped * cardWidth * _spacingFactor;
    return Matrix4.identity()
      ..setEntry(3, 2, 0.0012)
      ..translateByDouble(translateX, 0.0, 0.0, 1.0)
      ..rotateY(rotateY)
      // ignore: deprecated_member_use
      ..scale(scale);
  }

  double _dimForDelta(double delta) {
    final abs = delta.abs().clamp(0.0, 1.0);
    return 1.0 - ((1.0 - _sideDim) * abs);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount <= 0) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth * widget.viewportFraction;
        final focused = _reportedPage.clamp(0, widget.itemCount - 1);
        // Keep a stable window around the focused index so cards are not
        // constantly added/removed during a drag (floor/ceil churn).
        final start = math.max(0, focused - _visibleRadius);
        final end =
            math.min(widget.itemCount - 1, focused + _visibleRadius);
        final indices = [for (var i = start; i <= end; i++) i];
        final paintOrder = [...indices]
          ..sort(
            (a, b) => (b - focused).abs().compareTo((a - focused).abs()),
          );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          child: Stack(
            alignment: widget.alignment,
            clipBehavior: Clip.none,
            children: [
              IgnorePointer(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: widget.itemCount,
                  padEnds: widget.padEnds,
                  itemBuilder: (context, index) => const SizedBox.expand(),
                ),
              ),
              for (final index in paintOrder)
                AnimatedBuilder(
                  key: ValueKey<String>('cover-$index'),
                  animation: _controller,
                  builder: (context, child) {
                    final page = _controller.hasClients &&
                            _controller.position.haveDimensions
                        ? (_controller.page ?? focused.toDouble())
                        : focused.toDouble();
                    final delta = index - page;
                    return Transform(
                      alignment: Alignment.center,
                      transform: _transformForDelta(delta, cardWidth),
                      // Always wrap Opacity so focus changes do not remount.
                      child: Opacity(
                        opacity: _dimForDelta(delta),
                        child: child,
                      ),
                    );
                  },
                  child: SizedBox(
                    width: cardWidth,
                    height: constraints.maxHeight,
                    child: Align(
                      alignment: widget.alignment,
                      child: _CoverFlowCardHost(
                        index: index,
                        isFocused: index == focused,
                        itemBuilder: widget.itemBuilder,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Hosts one catalog card. Rebuilds only when [isFocused] / [index] change,
/// not on every Cover Flow scroll tick.
class _CoverFlowCardHost extends StatefulWidget {
  const _CoverFlowCardHost({
    required this.index,
    required this.isFocused,
    required this.itemBuilder,
  });

  final int index;
  final bool isFocused;
  final Widget Function(BuildContext context, int index, bool isFocused)
      itemBuilder;

  @override
  State<_CoverFlowCardHost> createState() => _CoverFlowCardHostState();
}

class _CoverFlowCardHostState extends State<_CoverFlowCardHost> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.isFocused
          ? null
          : () {
              final carousel =
                  context.findAncestorStateOfType<CoverFlowCarouselState>();
              carousel?.animateToPage(widget.index);
            },
      child: IgnorePointer(
        ignoring: !widget.isFocused,
        child: widget.itemBuilder(context, widget.index, widget.isFocused),
      ),
    );
  }
}
