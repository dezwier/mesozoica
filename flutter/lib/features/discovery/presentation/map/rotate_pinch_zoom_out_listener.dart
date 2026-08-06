import 'package:flutter/material.dart';

/// Transparent two-finger pinch-out detector used while FollowPuck owns zoom.
class RotatePinchZoomOutListener extends StatefulWidget {
  const RotatePinchZoomOutListener({super.key, required this.onZoomOut});

  final VoidCallback onZoomOut;
  static const double zoomOutSpanRatio = 0.88;

  @override
  State<RotatePinchZoomOutListener> createState() =>
      _RotatePinchZoomOutListenerState();
}

class _RotatePinchZoomOutListenerState
    extends State<RotatePinchZoomOutListener> {
  final Map<int, Offset> _pointers = {};
  double? _startSpan;
  bool _fired = false;

  double? _currentSpan() {
    if (_pointers.length < 2) return null;
    final points = _pointers.values.take(2).toList();
    return (points[0] - points[1]).distance;
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) {
      _startSpan = _currentSpan();
      _fired = false;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    final start = _startSpan;
    final now = _currentSpan();
    if (_fired || start == null || now == null || start <= 0) return;
    if (now / start <= RotatePinchZoomOutListener.zoomOutSpanRatio) {
      _fired = true;
      widget.onZoomOut();
    }
  }

  void _onPointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) {
      _startSpan = null;
      _fired = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: const SizedBox.expand(),
    );
  }
}
