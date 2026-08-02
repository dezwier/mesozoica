import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

import '../../controllers/terrain_echo_controller.dart';
import '../../models/site.dart';
import '../../services/location_service.dart';
import 'mapbox_camera_coordinator.dart';

/// Vintage brown/amber georeferenced radar around the player location.
class TerrainEchoOverlay extends StatefulWidget {
  const TerrainEchoOverlay({
    super.key,
    required this.camera,
  });

  final MapboxCameraCoordinator camera;

  @override
  State<TerrainEchoOverlay> createState() => _TerrainEchoOverlayState();
}

class _TerrainEchoOverlayState extends State<TerrainEchoOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;
  TerrainEchoController? _echo;
  VoidCallback? _echoListener;
  Timer? _projectTimer;
  int _projectSeq = 0;
  int _lastSitesRevision = -1;

  Offset? _centerPx;
  double _radiusPx = 0;
  List<_EchoBlip> _blips = const [];

  static const _amber = Color(0xFFC4A35A);
  static const _amberBright = Color(0xFFE8C060);
  static const _disc = Color(0xCC140E08);

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final echo = context.read<TerrainEchoController>();
    if (!identical(_echo, echo)) {
      _echo?.removeListener(_echoListener ?? () {});
      _echo = echo;
      _echoListener = _onEchoChanged;
      echo.addListener(_echoListener!);
      _syncActive(echo);
    }
  }

  @override
  void dispose() {
    _projectTimer?.cancel();
    _echo?.removeListener(_echoListener ?? () {});
    _sweep.dispose();
    super.dispose();
  }

  void _onEchoChanged() {
    final echo = _echo;
    if (echo == null) return;
    _syncActive(echo);
    if (echo.sitesRevision != _lastSitesRevision) {
      _lastSitesRevision = echo.sitesRevision;
      unawaited(_reproject());
    }
  }

  void _syncActive(TerrainEchoController echo) {
    final periodS = echo.sweepPeriodS.clamp(1.0, 60.0);
    final next = Duration(milliseconds: (periodS * 1000).round());
    if (_sweep.duration != next) {
      final progress = _sweep.isAnimating ? _sweep.value : 0.0;
      _sweep.duration = next;
      if (echo.isActive) {
        _sweep.repeat();
        _sweep.value = progress;
      } else {
        _sweep.stop();
      }
    } else if (echo.isActive && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!echo.isActive && _sweep.isAnimating) {
      _sweep.stop();
    }

    if (echo.isActive) {
      _projectTimer ??= Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => unawaited(_reproject()),
      );
      unawaited(_reproject());
    } else {
      _projectTimer?.cancel();
      _projectTimer = null;
      if (_centerPx != null || _blips.isNotEmpty) {
        setState(() {
          _centerPx = null;
          _radiusPx = 0;
          _blips = const [];
        });
      }
    }
  }

  Future<void> _reproject() async {
    final echo = _echo;
    if (echo == null || !echo.isActive || !mounted) {
      if (_centerPx != null || _blips.isNotEmpty) {
        setState(() {
          _centerPx = null;
          _radiusPx = 0;
          _blips = const [];
        });
      }
      return;
    }

    final origin = echo.origin ?? context.read<LocationService>().currentLocation;
    if (origin == null) return;

    final seq = ++_projectSeq;
    final rangeM = echo.rangeM;
    final east = _offsetMeters(origin, eastM: rangeM, northM: 0);

    final sitesInRange = <SiteSummary>[];
    for (final site in echo.discoverableSites) {
      final lat = site.latitude;
      final lon = site.longitude;
      if (lat == null || lon == null) continue;
      final d = Geolocator.distanceBetween(
        origin.latitude,
        origin.longitude,
        lat,
        lon,
      );
      if (d <= rangeM) sitesInRange.add(site);
    }

    final points = <LatLng>[
      origin,
      east,
      for (final s in sitesInRange)
        LatLng(s.latitude!, s.longitude!),
    ];
    final pixels = await widget.camera.pixelsForCoordinates(points);
    if (!mounted || seq != _projectSeq) return;

    final center = pixels.isNotEmpty ? pixels[0] : null;
    final edge = pixels.length > 1 ? pixels[1] : null;
    if (center == null || edge == null) return;

    final radiusPx = (edge - center).distance;
    if (radiusPx < 4) return;

    final accuracy = echo.accuracy.clamp(0.0, 1.0);
    final blips = <_EchoBlip>[];
    for (var i = 0; i < sitesInRange.length; i++) {
      final px = pixels[i + 2];
      if (px == null) continue;
      final site = sitesInRange[i];
      final jitterM = (1.0 - accuracy) * 8.0;
      final jitter = _stableJitter(site.siteId, jitterM, radiusPx / rangeM);
      blips.add(
        _EchoBlip(
          position: px + jitter,
          siteId: site.siteId,
        ),
      );
    }

    final centerChanged =
        _centerPx == null || (_centerPx! - center).distance > 0.5;
    final radiusChanged = (_radiusPx - radiusPx).abs() > 0.5;
    final blipsChanged = _blips.length != blips.length ||
        !_sameBlipPositions(_blips, blips);
    if (!centerChanged && !radiusChanged && !blipsChanged) return;

    setState(() {
      _centerPx = center;
      _radiusPx = radiusPx;
      _blips = blips;
    });
  }

  static bool _sameBlipPositions(List<_EchoBlip> a, List<_EchoBlip> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].siteId != b[i].siteId) return false;
      if ((a[i].position - b[i].position).distance > 0.5) return false;
    }
    return true;
  }

  static LatLng _offsetMeters(
    LatLng origin, {
    required double eastM,
    required double northM,
  }) {
    const metersPerDegLat = 111320.0;
    final latRad = origin.latitude * math.pi / 180.0;
    final metersPerDegLon = metersPerDegLat * math.cos(latRad).abs().clamp(0.2, 1.0);
    return LatLng(
      origin.latitude + northM / metersPerDegLat,
      origin.longitude + eastM / metersPerDegLon,
    );
  }

  static Offset _stableJitter(int siteId, double jitterM, double pxPerM) {
    if (jitterM <= 0 || pxPerM <= 0) return Offset.zero;
    final seed = siteId * 2654435761;
    final a = ((seed >> 16) & 0xffff) / 65535.0;
    final b = (seed & 0xffff) / 65535.0;
    final angle = a * math.pi * 2;
    final dist = b * jitterM * pxPerM;
    return Offset(math.cos(angle) * dist, math.sin(angle) * dist);
  }

  @override
  Widget build(BuildContext context) {
    final echo = context.watch<TerrainEchoController>();
    if (!echo.isActive) return const SizedBox.shrink();

    final center = _centerPx;
    if (center == null || _radiusPx < 4) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _TerrainEchoPainter(
            center: center,
            radiusPx: _radiusPx,
            rangeM: echo.rangeM,
            ringIncrementM: echo.ringIncrementM,
            degrees: echo.degrees,
            accuracy: echo.accuracy,
            sweepT: _sweep.value,
            blips: _blips,
            amber: _amber,
            amberBright: _amberBright,
            disc: _disc,
          ),
        ),
      ),
    );
  }
}

class _EchoBlip {
  const _EchoBlip({required this.position, required this.siteId});

  final Offset position;
  final int siteId;
}

class _TerrainEchoPainter extends CustomPainter {
  _TerrainEchoPainter({
    required this.center,
    required this.radiusPx,
    required this.rangeM,
    required this.ringIncrementM,
    required this.degrees,
    required this.accuracy,
    required this.sweepT,
    required this.blips,
    required this.amber,
    required this.amberBright,
    required this.disc,
  });

  final Offset center;
  final double radiusPx;
  final double rangeM;
  final double ringIncrementM;
  final double degrees;
  final double accuracy;
  final double sweepT;
  final List<_EchoBlip> blips;
  final Color amber;
  final Color amberBright;
  final Color disc;

  @override
  void paint(Canvas canvas, Size size) {
    final clip = Path()..addOval(Rect.fromCircle(center: center, radius: radiusPx));
    canvas.save();
    canvas.clipPath(clip);

    canvas.drawCircle(center, radiusPx, Paint()..color = disc);

    final ringPaint = Paint()
      ..color = amber.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final increment = ringIncrementM <= 0 ? 20.0 : ringIncrementM;
    final ringCount = (rangeM / increment).ceil().clamp(1, 20);
    for (var i = 1; i <= ringCount; i++) {
      final r = radiusPx * (i * increment / rangeM).clamp(0.0, 1.0);
      canvas.drawCircle(center, r, ringPaint);
    }

    final cross = Paint()
      ..color = amber.withValues(alpha: 0.4)
      ..strokeWidth = 0.9;
    canvas.drawLine(
      Offset(center.dx - radiusPx, center.dy),
      Offset(center.dx + radiusPx, center.dy),
      cross,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radiusPx),
      Offset(center.dx, center.dy + radiusPx),
      cross,
    );

    final sweepRad = sweepT * math.pi * 2;
    final wedgeRad = (degrees.clamp(1.0, 360.0) * math.pi / 180.0);
    // Leading edge at sweepRad; wedge trails clockwise (map "sideways" spin).
    final start = sweepRad - wedgeRad;
    final rect = Rect.fromCircle(center: center, radius: radiusPx);
    final gradient = ui.Gradient.sweep(
      center,
      [
        amberBright.withValues(alpha: 0.0),
        amber.withValues(alpha: 0.12),
        amberBright.withValues(alpha: 0.55),
      ],
      const [0.0, 0.55, 1.0],
      TileMode.clamp,
      start,
      sweepRad,
    );
    canvas.drawArc(
      rect,
      start,
      wedgeRad,
      true,
      Paint()..shader = gradient,
    );

    // Bright leading edge.
    final lead = Paint()
      ..color = amberBright.withValues(alpha: 0.85)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final leadEnd = Offset(
      center.dx + math.cos(sweepRad) * radiusPx,
      center.dy + math.sin(sweepRad) * radiusPx,
    );
    canvas.drawLine(center, leadEnd, lead);

    canvas.restore();

    // Outer rim (outside clip restore so it stays crisp).
    canvas.drawCircle(
      center,
      radiusPx,
      Paint()
        ..color = amber.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    final blurSigma = ui.lerpDouble(10.0, 1.2, accuracy.clamp(0.0, 1.0))!;
    final blipRadius = ui.lerpDouble(9.0, 3.0, accuracy.clamp(0.0, 1.0))!;
    for (final blip in blips) {
      final glow = Paint()
        ..color = amberBright.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma);
      canvas.drawCircle(blip.position, blipRadius * 1.6, glow);
      canvas.drawCircle(
        blip.position,
        blipRadius * 0.55,
        Paint()..color = amberBright.withValues(alpha: 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TerrainEchoPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.radiusPx != radiusPx ||
        oldDelegate.rangeM != rangeM ||
        oldDelegate.ringIncrementM != ringIncrementM ||
        oldDelegate.degrees != degrees ||
        oldDelegate.accuracy != accuracy ||
        oldDelegate.sweepT != sweepT ||
        oldDelegate.blips != blips;
  }
}
