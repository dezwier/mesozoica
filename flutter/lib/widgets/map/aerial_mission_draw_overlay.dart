import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../controllers/aerial_mission_controller.dart';
import '../../services/location_service.dart';
import 'mapbox_camera_coordinator.dart';

/// Full-screen draw layer for aerial mission scout loops.
///
/// One finger draws; two fingers pinch-zoom (map is covered by this overlay).
class AerialMissionDrawOverlay extends StatefulWidget {
  const AerialMissionDrawOverlay({
    super.key,
    required this.camera,
    required this.currentZoom,
    required this.onZoomChanged,
  });

  final MapboxCameraCoordinator camera;
  final double currentZoom;
  final ValueChanged<double> onZoomChanged;

  @override
  State<AerialMissionDrawOverlay> createState() => _AerialMissionDrawOverlayState();
}

class _AerialMissionDrawOverlayState extends State<AerialMissionDrawOverlay> {
  final List<Offset> _screenPoints = [];
  AerialMissionController? _recon;
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
    final recon = context.read<AerialMissionController>();
    if (!identical(recon, _recon)) {
      _recon?.removeListener(_onReconChanged);
      _recon = recon;
      _recon!.addListener(_onReconChanged);
    }
  }

  @override
  void didUpdateWidget(covariant AerialMissionDrawOverlay oldWidget) {
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
    final recon = context.read<AerialMissionController>();
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
    final recon = context.read<AerialMissionController>();
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
    final recon = context.read<AerialMissionController>();
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

  Future<void> _deployMission() async {
    final recon = context.read<AerialMissionController>();
    final location = context.read<LocationService>();
    final origin = location.currentLocation;
    if (origin == null) {
      recon.clearRoute(message: 'Waiting for your current location');
      setState(() => _screenPoints.clear());
      return;
    }
    final kind = recon.drawKind;
    final ok = await recon.deployMission(origin: origin);
    if (!mounted) return;
    if (!ok) {
      setState(() => _screenPoints.clear());
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(kind.deployedSnack)),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;

    if (_pointers.length >= 2) {
      // Pinch only — never start/clear a drawing.
      final recon = context.read<AerialMissionController>();
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
        final recon = context.read<AerialMissionController>();
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
    return Consumer2<AerialMissionController, LocationService>(
      builder: (context, recon, location, _) {
        if (!recon.isDrawMode) return const SizedBox.shrink();

        final top = MediaQuery.paddingOf(context).top + 12;
        final bottom = MediaQuery.paddingOf(context).bottom + 16;
        final scheme = Theme.of(context).colorScheme;
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
              Positioned(
                top: top,
                left: 16,
                right: 16,
                child: Material(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recon.message ??
                              'Draw with one finger; pinch to zoom. '
                              'The loop starts and ends at your location.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          recon.rangeHint,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        if (recon.hasRoute && recon.isShortRoute) ...[
                          const SizedBox(height: 8),
                          Text(
                            'This loop uses less than '
                            '${(recon.shortRouteWarnFraction * 100).round()}% '
                            'of the allowed range.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: bottom,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: recon.isSubmitting
                            ? null
                            : () => recon.cancelDraw(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                        ),
                        child: const Text(
                          'Abort Recon',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: recon.isSubmitting || !recon.hasRoute
                            ? null
                            : () {
                                recon.clearDrawnRoute();
                                setState(() {
                                  _screenPoints.clear();
                                  _markScreenDirty();
                                });
                              },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                        ),
                        child: const Text(
                          'Clear Route',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: recon.isSubmitting || !recon.hasRoute
                            ? null
                            : () {
                                unawaited(_deployMission());
                              },
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                        ),
                        child: recon.isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                kind.deployVerb,
                                textAlign: TextAlign.center,
                              ),
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
