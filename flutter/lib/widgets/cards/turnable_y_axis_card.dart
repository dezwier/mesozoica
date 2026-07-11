import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Y-axis 3D flip shell — tap left/right half or horizontal drag to turn.
class TurnableYAxisCard extends StatefulWidget {
  const TurnableYAxisCard({
    super.key,
    required this.front,
    required this.back,
    this.borderRadius = 16,
    this.outerPadding = const EdgeInsets.symmetric(vertical: 8.0),
    this.resetIdentity,
    this.fixedFaceHeight,
    this.prelayoutFacesForHeight = true,
    this.decoration,
  });

  final Widget front;
  final Widget back;
  final double borderRadius;
  final EdgeInsets outerPadding;
  final Object? resetIdentity;
  final double? fixedFaceHeight;
  final bool prelayoutFacesForHeight;
  final BoxDecoration? decoration;

  @override
  State<TurnableYAxisCard> createState() => _TurnableYAxisCardState();
}

class _TurnableYAxisCardState extends State<TurnableYAxisCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flipController;
  double _cardWidth = 1;
  bool _isDraggingHorizontally = false;
  double _lastTapTargetAngle = 0;

  static const double _halfTurnRadians = math.pi;
  static const double _fullTurnRadians = 2 * math.pi;
  static const double _swipeSensitivity = 2;
  static const SpringDescription _flipSpring = SpringDescription(
    mass: 1.5,
    stiffness: 100,
    damping: 12,
  );

  double get _rotationAngle => _flipController.value;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController.unbounded(
      vsync: this,
      value: 0,
      duration: const Duration(milliseconds: 260),
    )..addListener(() {
        if (!mounted) return;
        setState(() {});
      });
  }

  @override
  void didUpdateWidget(covariant TurnableYAxisCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetIdentity != oldWidget.resetIdentity) {
      _flipController.value = 0;
      _lastTapTargetAngle = 0;
    }
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _springSnapTo(
    double targetAngle, {
    double initialAngularVelocity = 0,
  }) {
    final simulation = SpringSimulation(
      _flipSpring,
      _rotationAngle,
      targetAngle,
      initialAngularVelocity,
    );
    _flipController.animateWith(simulation);
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _flipController.stop();
    _lastTapTargetAngle =
        (_rotationAngle / _halfTurnRadians).roundToDouble() * _halfTurnRadians;
    _isDraggingHorizontally = true;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final width = _cardWidth <= 0 ? 1 : _cardWidth;
    final dx = details.primaryDelta ?? 0;
    if (dx == 0) return;
    final deltaAngle = -((dx / width) * _swipeSensitivity) * _halfTurnRadians;
    _flipController.value = _rotationAngle + deltaAngle;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    _isDraggingHorizontally = false;
    final width = _cardWidth <= 0 ? 1 : _cardWidth;
    final vx = details.velocity.pixelsPerSecond.dx;
    final flingAngleOffset = vx.abs() > 700 ? (-(vx / width) * 0.18) : 0.0;
    final projected = _rotationAngle + flingAngleOffset;
    final target =
        (projected / _halfTurnRadians).roundToDouble() * _halfTurnRadians;
    _lastTapTargetAngle = target;
    const flingScale = 0.52;
    final initialAngularVelocity =
        -((vx / width) * _swipeSensitivity) * _halfTurnRadians * flingScale;
    _springSnapTo(
      target,
      initialAngularVelocity: initialAngularVelocity,
    );
  }

  void _onHorizontalDragCancel() {
    _isDraggingHorizontally = false;
    final target =
        (_rotationAngle / _halfTurnRadians).roundToDouble() * _halfTurnRadians;
    _lastTapTargetAngle = target;
    _springSnapTo(target);
  }

  double _normalizedAngle(double angle) {
    final normalized = angle % _fullTurnRadians;
    return normalized < 0 ? normalized + _fullTurnRadians : normalized;
  }

  double _normalizedSignedAngle(double angle) {
    final normalized = _normalizedAngle(angle);
    if (normalized > math.pi) return normalized - _fullTurnRadians;
    return normalized;
  }

  void _flipByOneFace({required bool turnLeft}) {
    final baseAngle =
        _flipController.isAnimating ? _lastTapTargetAngle : _rotationAngle;
    final snappedBase =
        (baseAngle / _halfTurnRadians).roundToDouble() * _halfTurnRadians;
    final target = turnLeft
        ? (snappedBase + _halfTurnRadians)
        : (snappedBase - _halfTurnRadians);
    _lastTapTargetAngle = target;
    _springSnapTo(target);
  }

  List<BoxShadow> _boxShadowForAngle(double angle) {
    final depth = math.sin(angle.abs()).clamp(0.0, 1.0);
    return [
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, 0.25 + depth * 0.2),
        blurRadius: 8 + depth * 8,
        offset: Offset(0, 4 + depth * 4),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.borderRadius;
    final cardContent = LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
          _cardWidth = constraints.maxWidth;
        }
        final measurementWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : _cardWidth;
        final fixedH = widget.fixedFaceHeight;
        final angle = _normalizedSignedAngle(_rotationAngle);
        final normalizedAngle = _normalizedAngle(angle);
        final sideTilt = 0.01 * math.sin(angle);
        final isBackVisible = normalizedAngle > (math.pi / 2) &&
            normalizedAngle < (3 * math.pi / 2);

        Widget visibleFace() {
          return isBackVisible
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: widget.back,
                )
              : widget.front;
        }

        final decoration = (widget.decoration ??
                BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(r),
                ))
            .copyWith(
          boxShadow: _boxShadowForAngle(angle),
        );

        return Stack(
          children: [
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0017)
                ..rotateY(angle)
                ..rotateZ(sideTilt)
                // ignore: deprecated_member_use
                ..scale(_isDraggingHorizontally ? 0.992 : 1.0),
              child: DecoratedBox(
                decoration: decoration,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(r),
                  clipBehavior: Clip.antiAlias,
                  child: fixedH != null && fixedH > 0 && measurementWidth > 0
                      ? SizedBox(
                          width: measurementWidth,
                          height: fixedH,
                          child: visibleFace(),
                        )
                      : !widget.prelayoutFacesForHeight
                          ? SizedBox.expand(child: visibleFace())
                          : Stack(
                              alignment: Alignment.topCenter,
                              children: [
                                ExcludeSemantics(
                                  child: IgnorePointer(
                                    child: Opacity(
                                      opacity: 0,
                                      child: widget.front,
                                    ),
                                  ),
                                ),
                                ExcludeSemantics(
                                  child: IgnorePointer(
                                    child: Opacity(
                                      opacity: 0,
                                      child: widget.back,
                                    ),
                                  ),
                                ),
                                Positioned.fill(child: visibleFace()),
                              ],
                            ),
                ),
              ),
            ),
          ],
        );
      },
    );

    final wrappedCard = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final tapX = details.localPosition.dx;
        final isLeftHalf = tapX <= (_cardWidth / 2);
        _flipByOneFace(turnLeft: isLeftHalf);
      },
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      onHorizontalDragCancel: _onHorizontalDragCancel,
      child: cardContent,
    );

    return Padding(
      padding: widget.outerPadding,
      child: wrappedCard,
    );
  }
}
