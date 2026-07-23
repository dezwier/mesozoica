import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart'
    show Point, Position;
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../controllers/aerial_recon_controller.dart';
import '../../services/location_service.dart';
import 'mapbox_camera_coordinator.dart';

/// Full-screen draw layer for Aerial Recon scout loops.
///
/// One finger draws; two fingers pinch-zoom (map is covered by this overlay).
class AerialReconDrawOverlay extends StatefulWidget {
  const AerialReconDrawOverlay({
    super.key,
    required this.camera,
    required this.currentZoom,
    required this.onZoomChanged,
  });

  final MapboxCameraCoordinator camera;
  final double currentZoom;
  final ValueChanged<double> onZoomChanged;

  @override
  State<AerialReconDrawOverlay> createState() => _AerialReconDrawOverlayState();
}

class _AerialReconDrawOverlayState extends State<AerialReconDrawOverlay> {
  final List<Offset> _screenPoints = [];
  AerialReconController? _recon;

  /// True while a one-finger draw stroke is active.
  bool _drawingGesture = false;

  /// True while a two-finger pinch is controlling zoom.
  bool _pinchGesture = false;
  double _pinchBaseZoom = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final recon = context.read<AerialReconController>();
    if (!identical(recon, _recon)) {
      _recon?.removeListener(_onReconChanged);
      _recon = recon;
      _recon!.addListener(_onReconChanged);
    }
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
        setState(() => _screenPoints.clear());
      }
    }
  }

  Future<Offset?> _screenFor(LatLng point) async {
    final map = widget.camera.map;
    if (map == null) return null;
    final screen = await map.pixelForCoordinate(
      Point(coordinates: Position(point.longitude, point.latitude)),
    );
    return Offset(screen.x.toDouble(), screen.y.toDouble());
  }

  Future<void> _handlePoint(Offset local, {required bool start}) async {
    final recon = context.read<AerialReconController>();
    final location = context.read<LocationService>();
    if (recon.isConfirming || recon.isSubmitting) return;
    final point = await widget.camera.coordinateForPixel(local);
    if (!mounted || point == null) return;
    final origin = location.currentLocation;
    if (start) {
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
      });
    } else {
      final before = recon.route.length;
      recon.appendPoint(point);
      if (recon.route.length > before) {
        setState(() => _screenPoints.add(local));
      }
    }
  }

  void _abortDrawForPinch() {
    final recon = context.read<AerialReconController>();
    recon.abortStroke();
    _drawingGesture = false;
    setState(() => _screenPoints.clear());
  }

  Future<void> _endStroke() async {
    final recon = context.read<AerialReconController>();
    final location = context.read<LocationService>();
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
    });
  }

  Future<void> _finishDrawing() async {
    final recon = context.read<AerialReconController>();
    final location = context.read<LocationService>();
    final origin = location.currentLocation;
    final ok = recon.finishDrawing(origin);
    if (!ok) {
      setState(() => _screenPoints.clear());
      return;
    }
    if (origin == null) return;
    final originScreen = await _screenFor(origin);
    if (!mounted || originScreen == null) return;
    setState(() {
      if (_screenPoints.isEmpty) {
        _screenPoints.add(originScreen);
        return;
      }
      _screenPoints[0] = originScreen;
      if (_screenPoints.length == 1) {
        _screenPoints.add(originScreen);
      } else {
        _screenPoints[_screenPoints.length - 1] = originScreen;
      }
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (details.pointerCount >= 2) {
      if (_drawingGesture) {
        _abortDrawForPinch();
      }
      _pinchGesture = true;
      _pinchBaseZoom = widget.currentZoom;
      return;
    }
    _pinchGesture = false;
    _drawingGesture = true;
    unawaited(_handlePoint(details.localFocalPoint, start: true));
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount >= 2) {
      if (_drawingGesture) {
        _abortDrawForPinch();
      }
      if (!_pinchGesture) {
        _pinchGesture = true;
        _pinchBaseZoom = widget.currentZoom;
      }
      // scale == 2 → +1 zoom level
      final next = (_pinchBaseZoom + math.log(details.scale) / math.ln2)
          .clamp(MapConfig.minZoom, MapConfig.maxZoom);
      widget.onZoomChanged(next.toDouble());
      return;
    }

    if (_pinchGesture) {
      // Returned to one finger after pinch — do not resume drawing this gesture.
      return;
    }
    if (_drawingGesture) {
      unawaited(_handlePoint(details.localFocalPoint, start: false));
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_drawingGesture && !_pinchGesture) {
      unawaited(_endStroke());
    }
    _drawingGesture = false;
    _pinchGesture = false;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AerialReconController, LocationService>(
      builder: (context, recon, location, _) {
        if (!recon.isDrawMode) return const SizedBox.shrink();

        final top = MediaQuery.paddingOf(context).top + 12;
        final bottom = MediaQuery.paddingOf(context).bottom + 16;
        final scheme = Theme.of(context).colorScheme;

        return Positioned.fill(
          child: Stack(
            children: [
              if (!recon.isConfirming)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: _onScaleEnd,
                  ),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ScreenRoutePainter(points: _screenPoints),
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
                          recon.isConfirming
                              ? 'Confirm scout route'
                              : (recon.message ??
                                  'Draw with one finger; pinch to zoom. '
                                  'The loop starts and ends at your location.'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          recon.isConfirming
                              ? 'Route length: '
                                  '${recon.routeLengthKm().toStringAsFixed(1)} km '
                                  '(allowed up to '
                                  '${_formatMax(recon.maxRouteKm)})'
                              : recon.rangeHint,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        if (recon.isConfirming && recon.isShortRoute) ...[
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
                child: recon.isConfirming
                    ? Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: recon.isSubmitting
                                  ? null
                                  : () {
                                      recon.redraw();
                                      setState(() => _screenPoints.clear());
                                    },
                              child: const Text('Redraw'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: recon.isSubmitting
                                  ? null
                                  : () async {
                                      final origin = location.currentLocation;
                                      if (origin == null) {
                                        recon.clearRoute(
                                          message:
                                              'Waiting for your current location',
                                        );
                                        setState(() => _screenPoints.clear());
                                        return;
                                      }
                                      final ok = await recon.confirmAndSubmit(
                                        origin: origin,
                                      );
                                      if (!context.mounted) return;
                                      if (ok) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Aerial Recon deployed — scouting in background',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                              child: recon.isSubmitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Deploy'),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: recon.isSubmitting
                                  ? null
                                  : () => recon.cancelDraw(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: recon.isSubmitting || !recon.hasRoute
                                  ? null
                                  : () {
                                      unawaited(_finishDrawing());
                                    },
                              child: const Text('Finish'),
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

  static String _formatMax(double km) {
    if (km == km.roundToDouble()) return '${km.toStringAsFixed(0)} km';
    return '${km.toStringAsFixed(1)} km';
  }
}

class _ScreenRoutePainter extends CustomPainter {
  _ScreenRoutePainter({required this.points});

  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = const Color(0xFFD4AF37)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);

    final dot = Paint()..color = const Color(0xFFD4AF37);
    canvas.drawCircle(points.first, 5, dot);
    canvas.drawCircle(points.last, 5, dot);
  }

  @override
  bool shouldRepaint(covariant _ScreenRoutePainter oldDelegate) =>
      oldDelegate.points != points;
}
