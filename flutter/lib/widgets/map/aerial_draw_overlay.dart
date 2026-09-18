import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../controllers/aerial_session_controller.dart';
import '../../models/aerial_action_kind.dart';
import '../../services/location_service.dart';
import '../common/app_toast.dart';
import 'active_tool_hud_shell.dart';
import 'mapbox_camera_coordinator.dart';
import 'vintage_guidance_compass.dart';

/// Full-screen draw layer for aerial scout-loop sessions.
///
/// One finger draws; two fingers pinch-zoom (map is covered by this overlay).
class AerialDrawOverlay extends StatefulWidget {
  const AerialDrawOverlay({
    super.key,
    required this.camera,
    required this.currentZoom,
    required this.onZoomChanged,
  });

  final MapboxCameraCoordinator camera;
  final double currentZoom;
  final ValueChanged<double> onZoomChanged;

  @override
  State<AerialDrawOverlay> createState() => _AerialDrawOverlayState();
}

class _AerialDrawOverlayState extends State<AerialDrawOverlay> {
  final List<Offset> _screenPoints = [];
  AerialSessionController? _recon;
  int _resyncToken = 0;
  int _paintEpoch = 0;

  final Map<int, Offset> _pointers = {};
  int? _drawPointer;
  Offset? _drawDownPos;
  bool _strokeStarted = false;
  bool _pinchActive = false;
  double _pinchBaseZoom = 0;
  double? _pinchBaseSpan;

  /// Zoom last applied to [_screenPoints] (for live pinch scaling).
  double _screenZoom = 0;

  static const _drawSlopPx = 10.0;

  void _markScreenDirty() => _paintEpoch++;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final recon = context.read<AerialSessionController>();
    if (!identical(recon, _recon)) {
      _recon?.removeListener(_onReconChanged);
      _recon = recon;
      _recon!.addListener(_onReconChanged);
    }
  }

  @override
  void didUpdateWidget(covariant AerialDrawOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentZoom == widget.currentZoom) return;
    if (_pinchActive) {
      // Pinch already scales [_screenPoints] live; wait for finger-up resync.
      return;
    }
    setState(() {
      _scaleScreenPointsToZoom(widget.currentZoom);
      _markScreenDirty();
    });
    unawaited(_resyncScreenFromRoute());
  }

  @override
  void dispose() {
    _recon?.removeListener(_onReconChanged);
    super.dispose();
  }

  void _onReconChanged() {
    final recon = _recon;
    if (recon == null) return;
    if (!recon.isDrawMode || recon.route.isEmpty) {
      if (_screenPoints.isNotEmpty) {
        setState(() {
          _screenPoints.clear();
          _markScreenDirty();
        });
      }
      return;
    }
    // Route mutated outside this overlay (e.g. clear) — keep screen in sync
    // when not actively stroking finger points.
    if (!_strokeStarted && !_pinchActive) {
      unawaited(_resyncScreenFromRoute());
    }
  }

  double? _currentSpan() {
    if (_pointers.length < 2) return null;
    final pts = _pointers.values.toList();
    return (pts[0] - pts[1]).distance;
  }

  Offset _mapFocal() {
    final size = MediaQuery.sizeOf(context);
    return Offset(size.width / 2, size.height / 2);
  }

  void _scaleScreenPointsToZoom(double toZoom) {
    if (_screenPoints.isEmpty) {
      _screenZoom = toZoom;
      return;
    }
    final delta = toZoom - _screenZoom;
    if (delta.abs() < 1e-6) return;
    final scale = math.pow(2.0, delta).toDouble();
    final focal = _mapFocal();
    for (var i = 0; i < _screenPoints.length; i++) {
      final p = _screenPoints[i];
      _screenPoints[i] = focal + (p - focal) * scale;
    }
    _screenZoom = toZoom;
  }

  Future<void> _resyncScreenFromRoute() async {
    final recon = _recon;
    if (recon == null || !recon.isDrawMode) return;
    final route = recon.route;
    if (route.isEmpty) {
      if (_screenPoints.isNotEmpty && mounted) {
        setState(() {
          _screenPoints.clear();
          _markScreenDirty();
        });
      }
      return;
    }
    final token = ++_resyncToken;
    // Ensure the map camera has the zoom we are projecting against.
    await widget.camera.setZoom(widget.currentZoom);
    if (!mounted || token != _resyncToken) return;
    final pixels = await widget.camera.pixelsForCoordinates(route);
    if (!mounted || token != _resyncToken) return;
    final next = <Offset>[];
    for (final pixel in pixels) {
      if (pixel != null) next.add(pixel);
    }
    if (next.length < 2 && route.length >= 2) return;
    setState(() {
      _screenPoints
        ..clear()
        ..addAll(next);
      _screenZoom = widget.currentZoom;
      _markScreenDirty();
    });
  }

  Future<Offset?> _screenFor(LatLng point) async {
    final pixels = await widget.camera.pixelsForCoordinates([point]);
    return pixels.isEmpty ? null : pixels.first;
  }

  Future<void> _startDrawAt(Offset local) async {
    final recon = context.read<AerialSessionController>();
    final location = context.read<LocationService>();
    if (recon.isSubmitting) return;

    // Resume a stroke paused by pinch instead of wiping it.
    if (recon.route.isNotEmpty && !recon.isDrawing) {
      recon.resumeStroke();
      _strokeStarted = true;
      await _appendDrawAt(local);
      return;
    }

    final point = await widget.camera.coordinateForPixel(local);
    if (!mounted || point == null) return;
    final origin = location.currentLocation;
    recon.startStroke(point, origin: origin);
    if (origin == null) return;
    final originScreen = await _screenFor(origin);
    if (!mounted) return;
    setState(() {
      _screenPoints
        ..clear()
        ..add(originScreen ?? local);
      if (recon.route.length > 1) {
        _screenPoints.add(local);
      }
      _markScreenDirty();
    });
    _strokeStarted = true;
    _screenZoom = widget.currentZoom;
  }

  Future<void> _appendDrawAt(Offset local) async {
    final recon = context.read<AerialSessionController>();
    if (recon.isSubmitting || !recon.isDrawing) return;
    final point = await widget.camera.coordinateForPixel(local);
    if (!mounted || point == null) return;
    final before = recon.route.length;
    recon.appendPoint(point);
    if (recon.route.length > before) {
      setState(() {
        _screenPoints.add(local);
        _markScreenDirty();
      });
    }
  }

  Future<void> _endStroke() async {
    final recon = context.read<AerialSessionController>();
    final location = context.read<LocationService>();
    if (!recon.isDrawing) return;
    final origin = location.currentLocation;
    recon.endStroke(origin: origin);
    if (origin == null) return;
    final originScreen = await _screenFor(origin);
    if (!mounted || originScreen == null) return;
    setState(() {
      if (_screenPoints.isEmpty) {
        _screenPoints.add(originScreen);
      } else {
        _screenPoints.add(originScreen);
      }
      _markScreenDirty();
    });
  }

  Future<void> _deploySession() async {
    final recon = context.read<AerialSessionController>();
    final location = context.read<LocationService>();
    final origin = location.currentLocation;
    if (origin == null) {
      recon.clearRoute(message: 'Waiting for your current location');
      setState(() => _screenPoints.clear());
      return;
    }
    final kind = recon.drawKind;
    final ok = await recon.deploySession(origin: origin);
    if (!mounted) return;
    if (!ok) {
      setState(() => _screenPoints.clear());
      return;
    }
    AppToast.success(context, kind.deployedSnack);
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;

    if (_pointers.length >= 2) {
      // Pinch only — never start/clear a drawing.
      final recon = context.read<AerialSessionController>();
      if (recon.isDrawing) {
        recon.pauseStroke();
      }
      _strokeStarted = false;
      _drawPointer = null;
      _drawDownPos = null;
      if (!_pinchActive) {
        _pinchActive = true;
        _pinchBaseZoom = widget.currentZoom;
        _pinchBaseSpan = _currentSpan();
      }
      return;
    }

    // Single finger — wait for move past slop before drawing.
    _pinchActive = false;
    _pinchBaseSpan = null;
    _drawPointer = event.pointer;
    _drawDownPos = event.localPosition;
    _strokeStarted = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;

    if (_pointers.length >= 2) {
      final span = _currentSpan();
      if (span == null) return;
      if (!_pinchActive) {
        _pinchActive = true;
        _pinchBaseZoom = widget.currentZoom;
        _pinchBaseSpan = span;
        _screenZoom = widget.currentZoom;
        final recon = context.read<AerialSessionController>();
        if (recon.isDrawing) {
          recon.pauseStroke();
        }
        _strokeStarted = false;
        _drawPointer = null;
        _drawDownPos = null;
      }
      final base = _pinchBaseSpan;
      if (base == null || base <= 0) return;
      final scale = span / base;
      final next = (_pinchBaseZoom + math.log(scale) / math.ln2)
          .clamp(MapConfig.minZoom, MapConfig.maxZoom)
          .toDouble();
      if ((next - _screenZoom).abs() > 1e-4) {
        setState(() {
          _scaleScreenPointsToZoom(next);
          _markScreenDirty();
        });
      }
      widget.onZoomChanged(next);
      return;
    }

    // One finger only.
    if (_pinchActive) return;
    if (event.pointer != _drawPointer || _drawDownPos == null) return;

    if (!_strokeStarted) {
      if ((event.localPosition - _drawDownPos!).distance < _drawSlopPx) {
        return;
      }
      unawaited(_startDrawAt(event.localPosition));
      return;
    }

    unawaited(_appendDrawAt(event.localPosition));
  }

  void _onPointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);

    if (_pointers.length >= 2) {
      _pinchBaseZoom = widget.currentZoom;
      _pinchBaseSpan = _currentSpan();
      return;
    }

    if (_pointers.length == 1) {
      // Leaving a pinch — reproject from geo so the route matches the map.
      if (_pinchActive) {
        _pinchActive = false;
        _pinchBaseSpan = null;
        unawaited(_resyncScreenFromRoute());
      }
      _drawPointer = null;
      _drawDownPos = null;
      _strokeStarted = false;
      return;
    }

    if (_pinchActive) {
      _pinchActive = false;
      _pinchBaseSpan = null;
      unawaited(_resyncScreenFromRoute());
    }

    if (_strokeStarted) {
      unawaited(_endStroke());
    }
    _drawPointer = null;
    _drawDownPos = null;
    _strokeStarted = false;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AerialSessionController, LocationService>(
      builder: (context, recon, location, _) {
        if (!recon.isDrawMode) return const SizedBox.shrink();

        final bottom = MediaQuery.paddingOf(context).bottom + 16;
        final kind = recon.drawKind;

        return Positioned.fill(
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerUp,
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ScreenRoutePainter(
                      points: _screenPoints,
                      epoch: _paintEpoch,
                      color: kind.activeRouteColor,
                    ),
                  ),
                ),
              ),
              VintageMapHudChip(
                maxWidth: 320,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      kind == AerialActionKind.scout ? 'SCOUT' : 'RECON',
                      style: VintageInstrumentStyle.mono.copyWith(
                        fontSize: 9,
                        letterSpacing: 1.2,
                        color: VintageInstrumentStyle.brassMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      recon.message ??
                          'Draw with one finger; pinch to zoom. '
                              'The loop starts and ends at your location.',
                      style: VintageInstrumentStyle.mono.copyWith(
                        fontSize: 10,
                        letterSpacing: 0.4,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: VintageInstrumentStyle.brassText,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      recon.rangeHint,
                      style: VintageInstrumentStyle.mono.copyWith(
                        fontSize: 9,
                        letterSpacing: 0.5,
                        color: VintageInstrumentStyle.brassMuted,
                      ),
                    ),
                    if (recon.hasRoute && recon.isShortRoute) ...[
                      const SizedBox(height: 6),
                      Text(
                        'SHORT LOOP · UNDER '
                        '${(recon.shortRouteWarnFraction * 100).round()}% RANGE',
                        style: VintageInstrumentStyle.mono.copyWith(
                          fontSize: 9,
                          letterSpacing: 0.7,
                          color: VintageInstrumentStyle.stop,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: bottom,
                child: Row(
                  children: [
                    Expanded(
                      child: _VintageDrawButton(
                        label: 'ABORT',
                        emphasized: false,
                        danger: true,
                        onPressed: recon.isSubmitting
                            ? null
                            : () => recon.cancelDraw(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _VintageDrawButton(
                        label: 'CLEAR',
                        emphasized: false,
                        onPressed: recon.isSubmitting || !recon.hasRoute
                            ? null
                            : () {
                                recon.clearDrawnRoute();
                                setState(() {
                                  _screenPoints.clear();
                                  _markScreenDirty();
                                });
                              },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _VintageDrawButton(
                        label: kind.deployVerb.toUpperCase(),
                        emphasized: true,
                        onPressed: recon.isSubmitting || !recon.hasRoute
                            ? null
                            : () {
                                unawaited(_deploySession());
                              },
                        busy: recon.isSubmitting,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VintageDrawButton extends StatelessWidget {
  const _VintageDrawButton({
    required this.label,
    required this.onPressed,
    this.emphasized = false,
    this.danger = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool emphasized;
  final bool danger;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final border = danger
        ? VintageInstrumentStyle.stop
        : emphasized
        ? VintageInstrumentStyle.gold
        : VintageInstrumentStyle.brassRim;
    final fg = !enabled
        ? VintageInstrumentStyle.brassMuted.withValues(alpha: 0.45)
        : danger
        ? VintageInstrumentStyle.stop
        : emphasized
        ? VintageInstrumentStyle.gold
        : VintageInstrumentStyle.brassText;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: VintageInstrumentStyle.dialFace.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: border.withValues(alpha: enabled ? 1 : 0.4),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Center(
              child: busy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: fg,
                      ),
                    )
                  : Text(
                      label,
                      textAlign: TextAlign.center,
                      style: VintageInstrumentStyle.mono.copyWith(
                        fontSize: 11,
                        letterSpacing: 1.0,
                        color: fg,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScreenRoutePainter extends CustomPainter {
  _ScreenRoutePainter({
    required this.points,
    required this.epoch,
    required this.color,
  });

  final List<Offset> points;
  final int epoch;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);

    final dot = Paint()..color = color;
    canvas.drawCircle(points.first, 5, dot);
    canvas.drawCircle(points.last, 5, dot);
  }

  @override
  bool shouldRepaint(covariant _ScreenRoutePainter oldDelegate) =>
      oldDelegate.epoch != epoch || oldDelegate.color != color;
}
