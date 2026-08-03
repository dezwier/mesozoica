import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

import '../../controllers/ridge_glass_controller.dart';
import '../../services/location_service.dart';
import 'mapbox_camera_coordinator.dart';
import 'vintage_guidance_compass.dart';

/// Dual location pulse while Ridge Glass is active.
///
/// Draws the baseline brown wave and the golden added-range wave with one
/// shared animation so they stay in phase. In rotate mode the rings are
/// foreshortened by pitch (same approach as Terrain Echo).
class RidgeGlassPulseOverlay extends StatefulWidget {
  const RidgeGlassPulseOverlay({
    super.key,
    required this.camera,
    required this.baseVisibilityM,
    required this.fullVisibilityM,
    required this.rotateWithHeading,
    required this.zoom,
  });

  final MapboxCameraCoordinator camera;
  final double baseVisibilityM;
  final double fullVisibilityM;
  final bool rotateWithHeading;
  final double zoom;

  /// Matches Mapbox LocationComponent default pulse duration.
  static const pulsePeriod = Duration(milliseconds: 2300);

  @override
  State<RidgeGlassPulseOverlay> createState() => _RidgeGlassPulseOverlayState();
}

class _RidgeGlassPulseOverlayState extends State<RidgeGlassPulseOverlay>
    with SingleTickerProviderStateMixin {
  static const _rimSamples = 64;

  late final AnimationController _pulse;
  Timer? _projectTimer;
  int _projectSeq = 0;
  bool _projectInFlight = false;
  bool _projectQueued = false;
  int _framesSinceProject = 0;

  Offset? _centerPx;
  double _innerRadiusPx = 0;
  double _outerRadiusPx = 0;
  double _bearingRad = 0;
  double _foreshorten = 1;
  double? _calibZoom;
  double? _calibOuterPx;
  double? _calibInnerPx;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: RidgeGlassPulseOverlay.pulsePeriod,
    )..addListener(_onPulseTick);
    _pulse.repeat();
  }

  void _onPulseTick() {
    if (widget.rotateWithHeading) {
      _framesSinceProject++;
      if (_framesSinceProject >= 2) {
        _framesSinceProject = 0;
        _requestReproject();
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant RidgeGlassPulseOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rangeChanged =
        oldWidget.baseVisibilityM != widget.baseVisibilityM ||
            oldWidget.fullVisibilityM != widget.fullVisibilityM;
    if (oldWidget.rotateWithHeading != widget.rotateWithHeading ||
        rangeChanged) {
      _restartProjectSchedule();
      _requestReproject();
    } else if (oldWidget.zoom != widget.zoom && _calibZoom != null) {
      _applyCalibratedGeometry(zoom: widget.zoom);
      _requestReproject();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restartProjectSchedule();
    _requestReproject();
  }

  @override
  void dispose() {
    _projectTimer?.cancel();
    _pulse.removeListener(_onPulseTick);
    _pulse.dispose();
    super.dispose();
  }

  void _restartProjectSchedule() {
    _projectTimer?.cancel();
    _projectTimer = null;
    // Rotate mode reprojects from the animation tick; north-fixed uses a timer.
    if (!widget.rotateWithHeading) {
      _projectTimer = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => _requestReproject(),
      );
    }
  }

  void _requestReproject() {
    if (_projectInFlight) {
      _projectQueued = true;
      return;
    }
    unawaited(_reproject());
  }

  Future<void> _reproject() async {
    _projectInFlight = true;
    final seq = ++_projectSeq;
    try {
      LocationService location;
      try {
        location = context.read<LocationService>();
      } on ProviderNotFoundException {
        return;
      }
      final loc = location.currentLocation;
      if (loc == null) return;

      final zoomAtProbe = widget.zoom;
      final attitude = await widget.camera.currentAttitude();
      if (!mounted || seq != _projectSeq) return;

      final bearingDeg =
          widget.rotateWithHeading ? (attitude?.bearing ?? 0.0) : 0.0;
      final pitchDeg =
          widget.rotateWithHeading ? (attitude?.pitch ?? 0.0) : 0.0;
      final bearing = bearingDeg * math.pi / 180.0;
      final foreshorten =
          math.cos(pitchDeg * math.pi / 180.0).clamp(0.2, 1.0);

      // Lateral probe (screen-right) — same calibration as Terrain Echo / puck.
      final rangeM = widget.fullVisibilityM;
      final probeM = math.min(8.0, rangeM * 0.1).clamp(2.0, 8.0);
      final rightEast = math.cos(bearing) * probeM;
      final rightNorth = -math.sin(bearing) * probeM;
      final probe = _offsetMeters(
        loc,
        eastM: rightEast,
        northM: rightNorth,
      );

      final pixels = await widget.camera.pixelsForCoordinates([loc, probe]);
      if (!mounted || seq != _projectSeq) return;
      final center = pixels.isNotEmpty ? pixels[0] : null;
      final probePx = pixels.length > 1 ? pixels[1] : null;
      if (center == null ||
          probePx == null ||
          !center.dx.isFinite ||
          !probePx.dx.isFinite) {
        return;
      }
      final probeDist = (probePx - center).distance;
      if (probeDist < 0.5) return;

      final outer = probeDist * (rangeM / probeM);
      final inner = widget.baseVisibilityM <= 0
          ? 0.0
          : probeDist * (widget.baseVisibilityM / probeM);
      if (outer < 4) return;

      _calibZoom = zoomAtProbe;
      _calibOuterPx = outer;
      _calibInnerPx = inner;
      _bearingRad = bearing;
      _foreshorten = foreshorten;
      _applyCalibratedGeometry(
        center: center,
        zoom: widget.zoom,
        bearingRad: bearing,
        foreshorten: foreshorten,
      );
    } finally {
      _projectInFlight = false;
      if (_projectQueued) {
        _projectQueued = false;
        SchedulerBinding.instance.scheduleFrameCallback((_) {
          if (mounted) _requestReproject();
        });
      }
    }
  }

  void _applyCalibratedGeometry({
    Offset? center,
    required double zoom,
    double? bearingRad,
    double? foreshorten,
  }) {
    final calibZoom = _calibZoom;
    final calibOuter = _calibOuterPx;
    final calibInner = _calibInnerPx;
    final c = center ?? _centerPx;
    if (calibZoom == null ||
        calibOuter == null ||
        calibInner == null ||
        c == null ||
        calibZoom <= 0) {
      return;
    }
    final scale = math.pow(2.0, zoom - calibZoom).toDouble();
    setState(() {
      _centerPx = c;
      _outerRadiusPx = (calibOuter * scale).clamp(8.0, 4096.0);
      _innerRadiusPx =
          (calibInner * scale).clamp(0.0, _outerRadiusPx * 0.98);
      if (bearingRad != null) _bearingRad = bearingRad;
      if (foreshorten != null) _foreshorten = foreshorten;
    });
  }

  static LatLng _offsetMeters(
    LatLng origin, {
    required double eastM,
    required double northM,
  }) {
    const metersPerDegLat = 111320.0;
    final latRad = origin.latitude * math.pi / 180.0;
    final metersPerDegLon =
        metersPerDegLat * math.cos(latRad).abs().clamp(0.2, 1.0);
    return LatLng(
      origin.latitude + northM / metersPerDegLat,
      origin.longitude + eastM / metersPerDegLon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ridge = context.watch<RidgeGlassController>();
    final center = _centerPx;
    if (!ridge.isActive ||
        center == null ||
        _outerRadiusPx <= _innerRadiusPx + 1) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: CustomPaint(
        painter: _RidgeGlassPulsePainter(
          center: center,
          innerRadius: _innerRadiusPx,
          outerRadius: _outerRadiusPx,
          bearingRad: _bearingRad,
          foreshorten: _foreshorten,
          progress: _pulse.value,
          brown: locationPuckPulseBrown,
          gold: VintageInstrumentStyle.gold,
          rimSamples: _rimSamples,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _RidgeGlassPulsePainter extends CustomPainter {
  _RidgeGlassPulsePainter({
    required this.center,
    required this.innerRadius,
    required this.outerRadius,
    required this.bearingRad,
    required this.foreshorten,
    required this.progress,
    required this.brown,
    required this.gold,
    required this.rimSamples,
  });

  final Offset center;
  final double innerRadius;
  final double outerRadius;
  final double bearingRad;
  final double foreshorten;
  final double progress;
  final Color brown;
  final Color gold;
  final int rimSamples;

  @override
  void paint(Canvas canvas, Size size) {
    if (outerRadius <= innerRadius) return;

    final innerPath = _ellipsePath(innerRadius);
    final outerPath = _ellipsePath(outerRadius);
    final band = Path.combine(PathOperation.difference, outerPath, innerPath);

    // Soft persistent gold wash over the added band.
    canvas.drawPath(
      band,
      Paint()
        ..color = gold.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill,
    );
    _strokeEllipse(
      canvas,
      outerRadius,
      Paint()
        ..color = gold.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    final waveR = progress * outerRadius;
    if (waveR <= 0) return;
    final fade = (1.0 - progress).clamp(0.0, 1.0);

    // Brown baseline wave — same progress as gold, clipped to inner disk.
    canvas.save();
    canvas.clipPath(innerPath);
    _drawWave(canvas, waveR, brown, fade);
    canvas.restore();

    // Gold bonus wave — same progress, clipped to outer annulus.
    if (waveR > innerRadius) {
      canvas.save();
      canvas.clipPath(band);
      _drawWave(canvas, waveR, gold, fade);
      canvas.restore();
    }
  }

  void _drawWave(Canvas canvas, double radius, Color color, double fade) {
    final fill = Paint()
      ..color = color.withValues(alpha: 0.22 * fade)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.85 * fade)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(_ellipsePath(radius), fill);
    _strokeEllipse(canvas, radius, stroke);
  }

  void _strokeEllipse(Canvas canvas, double radius, Paint paint) {
    final pts = _tiltedRing(radius);
    if (pts.length < 2) return;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  Path _ellipsePath(double radius) {
    final pts = _tiltedRing(radius);
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();
    return path;
  }

  List<Offset> _tiltedRing(double radiusPx) {
    return [
      for (var i = 0; i < rimSamples; i++)
        _groundToScreen(
          eastM: math.cos(i / rimSamples * math.pi * 2) * radiusPx,
          northM: math.sin(i / rimSamples * math.pi * 2) * radiusPx,
          radiusPx: radiusPx,
        ),
    ];
  }

  Offset _groundToScreen({
    required double eastM,
    required double northM,
    required double radiusPx,
  }) {
    final scale = radiusPx <= 0 ? 0.0 : 1.0;
    final right =
        (eastM * math.cos(bearingRad) - northM * math.sin(bearingRad)) * scale;
    final forward =
        (eastM * math.sin(bearingRad) + northM * math.cos(bearingRad)) * scale;
    return Offset(
      center.dx + right,
      center.dy - forward * foreshorten,
    );
  }

  @override
  bool shouldRepaint(covariant _RidgeGlassPulsePainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.innerRadius != innerRadius ||
        oldDelegate.outerRadius != outerRadius ||
        oldDelegate.bearingRad != bearingRad ||
        oldDelegate.foreshorten != foreshorten ||
        oldDelegate.progress != progress ||
        oldDelegate.brown != brown ||
        oldDelegate.gold != gold;
  }
}
