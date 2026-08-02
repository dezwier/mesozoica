import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

import '../../controllers/terrain_echo_controller.dart';
import '../../models/site.dart';
import '../../services/location_service.dart';
import 'mapbox_camera_coordinator.dart';

/// Vintage brown/amber georeferenced radar around the player location.
///
/// One visualization: a ground circle sized from a short on-screen probe.
/// North-fixed draws it as a circle; rotate foreshortens it by pitch into an
/// ellipse (same circle, tilted) — never projects the full range rim.
class TerrainEchoOverlay extends StatefulWidget {
  const TerrainEchoOverlay({
    super.key,
    required this.camera,
    this.rotateWithHeading = false,
  });

  final MapboxCameraCoordinator camera;

  /// When true, reproject every animation frame (FollowPuck moves continuously).
  final bool rotateWithHeading;

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
  double _prevSweepT = 0;

  bool _projectInFlight = false;
  bool _projectQueued = false;
  int _framesSinceProject = 0;

  Offset? _centerPx;
  List<Offset> _rimPx = const [];
  List<List<Offset>> _ringPx = const [];
  List<_EchoBlip> _blips = const [];
  final Map<int, double> _blipHitAtMs = {};

  static const _amber = Color(0xFFC4A35A);
  static const _amberBright = Color(0xFFE8C060);
  static const _discGrey = Color(0xFF3A342C);
  static const _discBrown = Color(0xFF2A2018);

  static const _rimSamples = 64;
  static const _helperRingCount = 3;
  static const _blipFadeS = 0.4;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(vsync: this)..addListener(_onSweepTick);
  }

  @override
  void didUpdateWidget(covariant TerrainEchoOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rotateWithHeading != widget.rotateWithHeading) {
      _restartProjectSchedule();
      _requestReproject();
    }
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
    _sweep.removeListener(_onSweepTick);
    _sweep.dispose();
    super.dispose();
  }

  void _onSweepTick() {
    _updateBlipHits(_prevSweepT, _sweep.value);
    _prevSweepT = _sweep.value;

    if (widget.rotateWithHeading && (_echo?.isActive ?? false)) {
      _framesSinceProject++;
      if (_framesSinceProject >= 2) {
        _framesSinceProject = 0;
        _requestReproject();
      }
    }

    if (mounted) setState(() {});
  }

  void _onEchoChanged() {
    final echo = _echo;
    if (echo == null) return;
    _syncActive(echo);
    if (echo.sitesRevision != _lastSitesRevision) {
      _lastSitesRevision = echo.sitesRevision;
      _requestReproject();
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
        _prevSweepT = progress;
      } else {
        _sweep.stop();
      }
    } else if (echo.isActive && !_sweep.isAnimating) {
      _sweep.repeat();
      _prevSweepT = _sweep.value;
    } else if (!echo.isActive && _sweep.isAnimating) {
      _sweep.stop();
    }

    if (echo.isActive) {
      _restartProjectSchedule();
      _requestReproject();
    } else {
      _projectTimer?.cancel();
      _projectTimer = null;
      _blipHitAtMs.clear();
      if (_centerPx != null || _rimPx.isNotEmpty) {
        setState(() {
          _centerPx = null;
          _rimPx = const [];
          _ringPx = const [];
          _blips = const [];
        });
      }
    }
  }

  void _restartProjectSchedule() {
    _projectTimer?.cancel();
    _projectTimer = null;
    if (!(_echo?.isActive ?? false)) return;
    if (!widget.rotateWithHeading) {
      _projectTimer = Timer.periodic(
        const Duration(milliseconds: 80),
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

  void _updateBlipHits(double prevT, double currT) {
    if (_blips.isEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    var prev = prevT % 1.0;
    var curr = currT % 1.0;
    if (prev < 0) prev += 1.0;
    if (curr < 0) curr += 1.0;
    if (curr < prev) curr += 1.0;

    for (final blip in _blips) {
      var hitT = blip.angleFrac % 1.0;
      if (hitT < 0) hitT += 1.0;
      if ((hitT > prev && hitT <= curr) ||
          (hitT + 1.0 > prev && hitT + 1.0 <= curr)) {
        _blipHitAtMs[blip.siteId] = nowMs;
      }
    }
  }

  static bool _finiteOffset(Offset? p) =>
      p != null && p.dx.isFinite && p.dy.isFinite;

  Future<void> _reproject() async {
    final echo = _echo;
    if (echo == null || !echo.isActive || !mounted) {
      if (_centerPx != null || _rimPx.isNotEmpty) {
        setState(() {
          _centerPx = null;
          _rimPx = const [];
          _ringPx = const [];
          _blips = const [];
        });
      }
      return;
    }

    _projectInFlight = true;
    final seq = ++_projectSeq;

    try {
      final origin =
          echo.origin ?? context.read<LocationService>().currentLocation;
      if (origin == null) return;

      final rangeM = echo.rangeM;
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

      await _reprojectGeometry(
        echo: echo,
        origin: origin,
        rangeM: rangeM,
        sitesInRange: sitesInRange,
        seq: seq,
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

  /// Same ground circle in both modes. Scale from a short lateral probe;
  /// rotate mode only adds pitch foreshortening (tilted ellipse).
  Future<void> _reprojectGeometry({
    required TerrainEchoController echo,
    required LatLng origin,
    required double rangeM,
    required List<SiteSummary> sitesInRange,
    required int seq,
  }) async {
    final attitude = await widget.camera.currentAttitude();
    if (!mounted || seq != _projectSeq) return;

    // North-fixed is locked north-up / pitch-0. Rotate uses live camera.
    final bearingDeg =
        widget.rotateWithHeading ? (attitude?.bearing ?? 0.0) : 0.0;
    final pitchDeg =
        widget.rotateWithHeading ? (attitude?.pitch ?? 0.0) : 0.0;
    final bearing = bearingDeg * math.pi / 180.0;
    final foreshorten =
        math.cos(pitchDeg * math.pi / 180.0).clamp(0.2, 1.0);

    // Lateral probe (screen-right) — stays near the puck at any zoom/pitch.
    final probeM = math.min(8.0, rangeM * 0.1).clamp(2.0, 8.0);
    final rightEast = math.cos(bearing) * probeM;
    final rightNorth = -math.sin(bearing) * probeM;
    final probe = _offsetMeters(
      origin,
      eastM: rightEast,
      northM: rightNorth,
    );

    final pixels = await widget.camera.pixelsForCoordinates([origin, probe]);
    if (!mounted || seq != _projectSeq) return;

    final center = pixels.isNotEmpty ? pixels[0] : null;
    final probePx = pixels.length > 1 ? pixels[1] : null;
    if (!_finiteOffset(center) || !_finiteOffset(probePx)) return;
    final centerPx = center!;
    final probeDist = (probePx! - centerPx).distance;
    if (probeDist < 0.5) return;
    final radiusPx = probeDist * (rangeM / probeM);
    if (radiusPx < 4) return;

    final rings = <List<Offset>>[
      for (var r = 1; r <= _helperRingCount; r++)
        _tiltedRing(
          center: centerPx,
          radiusPx: radiusPx * (r / _helperRingCount),
          bearingRad: bearing,
          foreshorten: foreshorten,
        ),
    ];
    final rim = rings.last;

    final accuracy = echo.accuracy.clamp(0.0, 1.0);
    final blips = <_EchoBlip>[];
    for (var i = 0; i < sitesInRange.length; i++) {
      final site = sitesInRange[i];
      final geo = _geoEastNorthMeters(
        origin,
        LatLng(site.latitude!, site.longitude!),
      );
      final angle = math.atan2(geo.dy, geo.dx);
      var angleFrac = angle / (math.pi * 2);
      angleFrac %= 1.0;
      if (angleFrac < 0) angleFrac += 1.0;

      var pos = _groundToScreen(
        center: centerPx,
        eastM: geo.dx,
        northM: geo.dy,
        rangeM: rangeM,
        radiusPx: radiusPx,
        bearingRad: bearing,
        foreshorten: foreshorten,
      );

      final jitterFrac = (1.0 - accuracy) * 0.08;
      if (jitterFrac > 0) {
        pos = Offset.lerp(pos, _rimAt(rim, angleFrac), jitterFrac)!;
      }

      blips.add(
        _EchoBlip(position: pos, angleFrac: angleFrac, siteId: site.siteId),
      );
    }

    final liveIds = {for (final b in blips) b.siteId};
    _blipHitAtMs.removeWhere((id, _) => !liveIds.contains(id));

    if (!mounted || seq != _projectSeq) return;
    setState(() {
      _centerPx = centerPx;
      _rimPx = rim;
      _ringPx = rings;
      _blips = blips;
    });
  }

  /// Geographic east/north → screen, with map bearing and pitch foreshorten.
  static Offset _groundToScreen({
    required Offset center,
    required double eastM,
    required double northM,
    required double rangeM,
    required double radiusPx,
    required double bearingRad,
    required double foreshorten,
  }) {
    final scale = radiusPx / rangeM;
    final right =
        (eastM * math.cos(bearingRad) - northM * math.sin(bearingRad)) * scale;
    final forward =
        (eastM * math.sin(bearingRad) + northM * math.cos(bearingRad)) * scale;
    return Offset(
      center.dx + right,
      center.dy - forward * foreshorten,
    );
  }

  static List<Offset> _tiltedRing({
    required Offset center,
    required double radiusPx,
    required double bearingRad,
    required double foreshorten,
  }) {
    return [
      for (var i = 0; i < _rimSamples; i++)
        _groundToScreen(
          center: center,
          eastM: math.cos(i / _rimSamples * math.pi * 2) * radiusPx,
          northM: math.sin(i / _rimSamples * math.pi * 2) * radiusPx,
          rangeM: radiusPx, // eastM/northM already in px-equivalent units
          radiusPx: radiusPx,
          bearingRad: bearingRad,
          foreshorten: foreshorten,
        ),
    ];
  }

  static Offset _rimAt(List<Offset> rim, double angleFrac) {
    if (rim.isEmpty) return Offset.zero;
    final n = rim.length;
    final f = ((angleFrac % 1.0) + 1.0) % 1.0 * n;
    final i0 = f.floor() % n;
    final i1 = (i0 + 1) % n;
    final u = f - f.floor();
    return Offset.lerp(rim[i0], rim[i1], u)!;
  }

  static Offset _geoEastNorthMeters(LatLng origin, LatLng target) {
    const metersPerDegLat = 111320.0;
    final latRad = origin.latitude * math.pi / 180.0;
    final metersPerDegLon =
        metersPerDegLat * math.cos(latRad).abs().clamp(0.2, 1.0);
    final north = (target.latitude - origin.latitude) * metersPerDegLat;
    final east = (target.longitude - origin.longitude) * metersPerDegLon;
    return Offset(east, north);
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

  Map<int, double> _blipAlphas() {
    final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    final fadeMs = _blipFadeS * 1000.0;
    final out = <int, double>{};
    for (final entry in _blipHitAtMs.entries) {
      final age = nowMs - entry.value;
      if (age < 0 || age >= fadeMs) continue;
      final t = 1.0 - (age / fadeMs);
      out[entry.key] = Curves.easeOut.transform(t);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final echo = context.watch<TerrainEchoController>();
    if (!echo.isActive) return const SizedBox.shrink();

    final center = _centerPx;
    if (center == null || _rimPx.length < 8 || _ringPx.length != 3) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _TerrainEchoPainter(
            center: center,
            rimPx: _rimPx,
            ringPx: _ringPx,
            degrees: echo.degrees,
            accuracy: echo.accuracy,
            sweepT: _sweep.value,
            blips: _blips,
            blipAlphas: _blipAlphas(),
            amber: _amber,
            amberBright: _amberBright,
            discGrey: _discGrey,
            discBrown: _discBrown,
          ),
        ),
      ),
    );
  }
}

class _EchoBlip {
  const _EchoBlip({
    required this.position,
    required this.angleFrac,
    required this.siteId,
  });

  final Offset position;
  final double angleFrac;
  final int siteId;
}

class _TerrainEchoPainter extends CustomPainter {
  _TerrainEchoPainter({
    required this.center,
    required this.rimPx,
    required this.ringPx,
    required this.degrees,
    required this.accuracy,
    required this.sweepT,
    required this.blips,
    required this.blipAlphas,
    required this.amber,
    required this.amberBright,
    required this.discGrey,
    required this.discBrown,
  });

  final Offset center;
  final List<Offset> rimPx;
  final List<List<Offset>> ringPx;
  final double degrees;
  final double accuracy;
  final double sweepT;
  final List<_EchoBlip> blips;
  final Map<int, double> blipAlphas;
  final Color amber;
  final Color amberBright;
  final Color discGrey;
  final Color discBrown;

  Path _pathFrom(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final p = pts[i];
      if (!p.dx.isFinite || !p.dy.isFinite) continue;
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    return path;
  }

  Offset _rimAtFrac(double angleFrac) {
    final n = rimPx.length;
    final f = ((angleFrac % 1.0) + 1.0) % 1.0 * n;
    final i0 = f.floor() % n;
    final i1 = (i0 + 1) % n;
    final u = f - f.floor();
    return Offset.lerp(rimPx[i0], rimPx[i1], u)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final discPath = _pathFrom(rimPx);
    final discShader = ui.Gradient.linear(
      rimPx.first,
      rimPx[rimPx.length ~/ 2],
      [
        discGrey.withValues(alpha: 0.16),
        discBrown.withValues(alpha: 0.16),
      ],
    );
    canvas.drawPath(discPath, Paint()..shader = discShader);

    final ringPaint = Paint()
      ..color = amber.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..isAntiAlias = true;
    for (final ring in ringPx) {
      canvas.drawPath(_pathFrom(ring), ringPaint);
    }

    final crossPaint = Paint()
      ..color = amber.withValues(alpha: 0.35)
      ..strokeWidth = 0.9
      ..isAntiAlias = true;
    final n = rimPx.length;
    canvas.drawLine(rimPx[0], rimPx[n ~/ 2], crossPaint);
    canvas.drawLine(rimPx[n ~/ 4], rimPx[(3 * n) ~/ 4], crossPaint);

    final sweepFrac = ((sweepT % 1.0) + 1.0) % 1.0;
    final wedgeFrac = (degrees.clamp(1.0, 360.0) / 360.0).clamp(0.01, 1.0);
    const segments = 36;
    canvas.save();
    canvas.clipPath(discPath);
    for (var i = 0; i < segments; i++) {
      final t0 = i / segments;
      final t1 = (i + 1) / segments;
      final a0 = sweepFrac - wedgeFrac * (1.0 - t0);
      final a1 = sweepFrac - wedgeFrac * (1.0 - t1);
      final p0 = _rimAtFrac(a0);
      final p1 = _rimAtFrac(a1);
      final strength = Curves.easeIn.transform(t1);
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(p0.dx, p0.dy)
        ..lineTo(p1.dx, p1.dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = amberBright.withValues(alpha: 0.38 * strength)
          ..isAntiAlias = true,
      );
    }

    final leadEnd = _rimAtFrac(sweepFrac);
    canvas.drawLine(
      center,
      leadEnd,
      Paint()
        ..color = amberBright.withValues(alpha: 0.9)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
    canvas.restore();

    canvas.drawPath(
      discPath,
      Paint()
        ..color = amber.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..isAntiAlias = true,
    );

    final span = rimPx.fold<double>(
      0,
      (m, p) => math.max(m, (p - center).distance),
    );
    final blurSigma = ui.lerpDouble(10.0, 2.0, accuracy.clamp(0.0, 1.0))!;
    final blipRadius = ui
        .lerpDouble(
          (span * 0.06).clamp(10.0, 26.0),
          (span * 0.025).clamp(5.0, 12.0),
          accuracy.clamp(0.0, 1.0),
        )!
        .toDouble();
    for (final blip in blips) {
      final alpha = blipAlphas[blip.siteId] ?? 0.0;
      if (alpha <= 0.01) continue;
      if (!blip.position.dx.isFinite || !blip.position.dy.isFinite) continue;
      canvas.drawCircle(
        blip.position,
        blipRadius * 1.7,
        Paint()
          ..color = amberBright.withValues(alpha: 0.4 * alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma),
      );
      canvas.drawCircle(
        blip.position,
        blipRadius * 0.5,
        Paint()..color = amberBright.withValues(alpha: 0.95 * alpha),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TerrainEchoPainter oldDelegate) {
    return oldDelegate.center != center ||
        !identical(oldDelegate.rimPx, rimPx) ||
        !identical(oldDelegate.ringPx, ringPx) ||
        oldDelegate.degrees != degrees ||
        oldDelegate.accuracy != accuracy ||
        oldDelegate.sweepT != sweepT ||
        !identical(oldDelegate.blips, blips) ||
        oldDelegate.blipAlphas != blipAlphas;
  }
}
