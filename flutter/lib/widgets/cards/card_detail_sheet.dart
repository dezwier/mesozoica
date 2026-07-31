import 'dart:async';

import 'package:flutter/material.dart';

/// Shared presentation for card detail overlays (map taps, cross-links).
///
/// Catalog screens embed turnable cards inline; this sheet is only for the
/// floating overlays that appear in front of the map / other tabs.
///
/// [openCount] lets [AppShell] freeze the map and hide chrome while any card
/// dialog is up (same treatment as catalog / tools overlays).
class CardDetailSheet {
  CardDetailSheet._();

  /// Nested show/dismiss depth; AppShell listens to hide map chrome + freeze.
  static final ValueNotifier<int> openCount = ValueNotifier<int>(0);

  static bool get isOpen => openCount.value > 0;

  static const double bottomGap = 16;

  /// Extra lift so the card sits above the home indicator, leaving a tappable
  /// dismiss band below. Map chrome is hidden while the sheet is open.
  static const double cardLift = 56;

  static double bottomOffset(BuildContext context) {
    return bottomGap + cardLift + MediaQuery.paddingOf(context).bottom;
  }

  static double maxContentHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    return size.height - bottomOffset(context) - padding.top - 8;
  }

  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) {
    final barrierLabel =
        MaterialLocalizations.of(context).modalBarrierDismissLabel;
    openCount.value += 1;
    return showGeneralDialog<T>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: barrierLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) {
        return CardDetailSheetShell(child: builder(context));
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ).whenComplete(() {
      if (openCount.value > 0) {
        openCount.value -= 1;
      }
    });
  }
}

class CardDetailSheetShell extends StatelessWidget {
  const CardDetailSheetShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Only as tall as the card: the dialog barrier fills the rest, so taps
    // above *and* below dismiss (barrierDismissible).
    return Padding(
      padding: EdgeInsets.only(bottom: CardDetailSheet.bottomOffset(context)),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: _VerticalDismissible(
          onDismiss: () => Navigator.of(context).maybePop(),
          child: Material(
            color: Colors.transparent,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Drag up or down past a threshold / fling to dismiss.
///
/// Uses a [Listener] (not a competing vertical [GestureDetector]) so it works
/// alongside the card's horizontal flip gesture.
class _VerticalDismissible extends StatefulWidget {
  const _VerticalDismissible({
    required this.child,
    required this.onDismiss,
  });

  final Widget child;
  final VoidCallback onDismiss;

  @override
  State<_VerticalDismissible> createState() => _VerticalDismissibleState();
}

class _VerticalDismissibleState extends State<_VerticalDismissible>
    with SingleTickerProviderStateMixin {
  static const double _dismissDistance = 110;
  static const double _dismissVelocity = 900;
  static const double _axisLockSlop = 14;

  late final AnimationController _controller;
  Animation<double>? _offsetAnimation;

  double _dragOffset = 0;
  bool _dismissing = false;

  int? _pointer;
  Offset _pointerStart = Offset.zero;
  double _lastY = 0;
  double _velocityY = 0;
  Duration _lastTime = Duration.zero;
  _AxisLock _axisLock = _AxisLock.none;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _offset => _offsetAnimation?.value ?? _dragOffset;

  void _onPointerDown(PointerDownEvent event) {
    if (_dismissing || _pointer != null) return;
    _controller.stop();
    _offsetAnimation = null;
    _pointer = event.pointer;
    _pointerStart = event.position;
    _lastY = event.position.dy;
    _lastTime = event.timeStamp;
    _velocityY = 0;
    _axisLock = _AxisLock.none;
    _dragOffset = 0;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _dismissing) return;

    final delta = event.position - _pointerStart;
    if (_axisLock == _AxisLock.none) {
      if (delta.distance < _axisLockSlop) return;
      _axisLock = delta.dx.abs() > delta.dy.abs()
          ? _AxisLock.horizontal
          : _AxisLock.vertical;
      if (_axisLock == _AxisLock.horizontal) return;
    } else if (_axisLock == _AxisLock.horizontal) {
      return;
    }

    final dt = (event.timeStamp - _lastTime).inMicroseconds / 1e6;
    if (dt > 0) {
      _velocityY = (event.position.dy - _lastY) / dt;
    }
    _lastY = event.position.dy;
    _lastTime = event.timeStamp;

    setState(() => _dragOffset = delta.dy);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    if (_axisLock != _AxisLock.vertical || _dismissing) {
      _axisLock = _AxisLock.none;
      if (_dragOffset != 0 && !_dismissing) {
        unawaited(_animateTo(0));
      }
      return;
    }
    _axisLock = _AxisLock.none;
    _onDragEnd(_velocityY);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _axisLock = _AxisLock.none;
    if (!_dismissing && _dragOffset != 0) {
      unawaited(_animateTo(0));
    }
  }

  void _onDragEnd(double velocity) {
    if (_dismissing) return;
    final shouldDismiss =
        _dragOffset.abs() > _dismissDistance || velocity.abs() > _dismissVelocity;
    if (!shouldDismiss) {
      unawaited(_animateTo(0));
      return;
    }
    final flingDown = _dragOffset.abs() > 1 ? _dragOffset > 0 : velocity >= 0;
    unawaited(_finishDismiss(flingDown: flingDown));
  }

  Future<void> _animateTo(double target, {Duration? duration}) async {
    final start = _dragOffset;
    _offsetAnimation = Tween<double>(begin: start, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    )..addListener(() {
        if (!mounted) return;
        setState(() => _dragOffset = _offsetAnimation!.value);
      });
    _controller.duration = duration ?? const Duration(milliseconds: 200);
    _controller.reset();
    await _controller.forward();
    if (!mounted) return;
    _offsetAnimation = null;
    setState(() => _dragOffset = target);
  }

  Future<void> _finishDismiss({required bool flingDown}) async {
    if (_dismissing) return;
    _dismissing = true;
    final screenH = MediaQuery.sizeOf(context).height;
    await _animateTo(
      flingDown ? screenH : -screenH,
      duration: const Duration(milliseconds: 220),
    );
    if (!mounted) return;
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Transform.translate(
        offset: Offset(0, _offset),
        child: widget.child,
      ),
    );
  }
}

enum _AxisLock { none, horizontal, vertical }

/// Card body capped by [CardDetailSheet.maxContentHeight].
///
/// No inner scroll view — fixed-aspect turnable cards fit, and a scrollable
/// would fight vertical dismiss. Celebration titles still fit on small phones.
class CardDetailSheetContent extends StatelessWidget {
  const CardDetailSheetContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: CardDetailSheet.maxContentHeight(context),
      ),
      child: child,
    );
  }
}
