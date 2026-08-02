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
    required this.zoom,
  });

  final MapboxCameraCoordinator camera;

  /// When true, reproject every animation frame (FollowPuck moves continuously).
  final bool rotateWithHeading;

  /// Live map zoom — used to scale the circle instantly while pinching.
  final double zoom;

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
  List<_EchoBlip> _blips = const [];
  final Map<int, double> _blipHitAtMs = {};

  /// Last probe calibration — live zoom scales from this without awaiting Mapbox.
  double? _calibZoom;
  double? _calibRadiusPx;
  double _calibBearing = 0;
  double _calibForeshorten = 1;
  double _calibRangeM = 1;
  double _calibAccuracy = 1;
  List<_CalibBlip> _calibBlips = const [];

  static const _sweepColor = Color(0xFFC4A35A);
  static const _discColor = Color(0xFF3A2E24);
  static const _blipColor = Color(0xFF6B4A36);

  static const _rimSamples = 64;
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
    } else if (oldWidget.zoom != widget.zoom && _calibZoom != null) {
      // Instant mercator scale — no round-trip to Mapbox.
      _applyCalibratedGeometry(
        center: _centerPx,
        zoom: widget.zoom,
      );
      // Coalesced probe to correct center if the zoom focal point shifted it.
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
      _clearCalibration();
      if (_centerPx != null || _rimPx.isNotEmpty) {
        setState(() {
          _centerPx = null;
          _rimPx = const [];
          _blips = const [];
        });
      }
    }
  }

  void _clearCalibration() {
    _calibZoom = null;
    _calibRadiusPx = null;
    _calibBlips = const [];
  }

  void _restartProjectSchedule() {
    _projectTimer?.cancel();
    _projectTimer = null;
    if (!(_echo?.isActive ?? false)) return;
    // Zoom is live-scaled; timer only recalibrates center after pan/settle.
    if (!widget.rotateWithHeading) {
      _projectTimer = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => _requestReproject(),
      );
    }
  }

  /// Rebuild rim/blips from the last probe using mercator zoom scaling.
  void _applyCalibratedGeometry({
    required Offset? center,
    required double zoom,
    double? bearingRad,
    double? foreshorten,
  }) {
    final calibZoom = _calibZoom;
    final calibRadius = _calibRadiusPx;
    if (center == null || calibZoom == null || calibRadius == null) return;

    final radiusPx =
        calibRadius * math.pow(2.0, zoom - calibZoom).toDouble();
    if (radiusPx < 4) return;

    final bearing = bearingRad ?? _calibBearing;
    final fore = foreshorten ?? _calibForeshorten;
    final rangeM = _calibRangeM;
    final accuracy = _calibAccuracy;

    final rim = _tiltedRing(
      center: center,
      radiusPx: radiusPx,
      bearingRad: bearing,
      foreshorten: fore,
    );

    final blips = <_EchoBlip>[];
    for (final b in _calibBlips) {
      var pos = _groundToScreen(
        center: center,
        eastM: b.eastM,
        northM: b.northM,
        rangeM: rangeM,
        radiusPx: radiusPx,
        bearingRad: bearing,
        foreshorten: fore,
      );
      final jitterFrac = (1.0 - accuracy) * 0.08;
      if (jitterFrac > 0) {
        pos = Offset.lerp(pos, _rimAt(rim, b.angleFrac), jitterFrac)!;
      }
      blips.add(
        _EchoBlip(position: pos, angleFrac: b.angleFrac, siteId: b.siteId),
      );
    }

    setState(() {
      _centerPx = center;
      _rimPx = rim;
      _blips = blips;
    });
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
    // Capture zoom before awaits — radius is valid for this zoom.
    final zoomAtProbe = widget.zoom;

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

    final accuracy = echo.accuracy.clamp(0.0, 1.0);
    final calibBlips = <_CalibBlip>[];
    for (final site in sitesInRange) {
      final geo = _geoEastNorthMeters(
        origin,
        LatLng(site.latitude!, site.longitude!),
      );
      final angle = math.atan2(geo.dy, geo.dx);
      var angleFrac = angle / (math.pi * 2);
      angleFrac %= 1.0;
      if (angleFrac < 0) angleFrac += 1.0;
      calibBlips.add(
        _CalibBlip(
          eastM: geo.dx,
          northM: geo.dy,
          angleFrac: angleFrac,
          siteId: site.siteId,
        ),
      );
    }

    final liveIds = {for (final b in calibBlips) b.siteId};
    _blipHitAtMs.removeWhere((id, _) => !liveIds.contains(id));

    if (!mounted || seq != _projectSeq) return;

    _calibZoom = zoomAtProbe;
    _calibRadiusPx = radiusPx;
    _calibBearing = bearing;
    _calibForeshorten = foreshorten;
    _calibRangeM = rangeM;
    _calibAccuracy = accuracy;
    _calibBlips = calibBlips;

    // Apply at the live zoom so a pinch during the await doesn't jump.
    _applyCalibratedGeometry(
      center: centerPx,
      zoom: widget.zoom,
      bearingRad: bearing,
      foreshorten: foreshorten,
    );
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
    if (center == null || _rimPx.length < 8) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _TerrainEchoPainter(
            center: center,
            rimPx: _rimPx,
            degrees: echo.degrees,
            accuracy: echo.accuracy,
            sweepT: _sweep.value,
            blips: _blips,
            blipAlphas: _blipAlphas(),
            sweepColor: _sweepColor,
            discColor: _discColor,
            blipColor: _blipColor,
          ),
        ),
      ),
    );
  }
}

class _CalibBlip {
  const _CalibBlip({
    required this.eastM,
    required this.northM,
    required this.angleFrac,
    required this.siteId,
  });

  final double eastM;
  final double northM;
  final double angleFrac;
  final int siteId;
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
    required this.degrees,
    required this.accuracy,
    required this.sweepT,
    required this.blips,
    required this.blipAlphas,
    required this.sweepColor,
    required this.discColor,
    required this.blipColor,
  });

  final Offset center;
  final List<Offset> rimPx;
  final double degrees;
  final double accuracy;
  final double sweepT;
  final List<_EchoBlip> blips;
  final Map<int, double> blipAlphas;
  final Color sweepColor;
  final Color discColor;
  final Color blipColor;

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
    final span = rimPx.fold<double>(
      0,
      (m, p) => math.max(m, (p - center).distance),
    );

    // Subtle disc + short soft falloff that follows the rim (circle or ellipse).
    canvas.save();
    canvas.clipPath(discPath);
    canvas.drawPaint(Paint()..color = discColor.withValues(alpha: 0.055));
    canvas.restore();
    canvas.drawPath(
      discPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (span * 0.04).clamp(6.0, 14.0)
        ..color = discColor.withValues(alpha: 0.05)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
        ..isAntiAlias = true,
    );

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
          ..color = sweepColor.withValues(alpha: 0.22 * strength)
          ..isAntiAlias = true,
      );
    }

    final leadEnd = _rimAtFrac(sweepFrac);
    canvas.drawLine(
      center,
      leadEnd,
      Paint()
        ..color = sweepColor.withValues(alpha: 0.55)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
    canvas.restore();

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
          ..color = blipColor.withValues(alpha: 0.45 * alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma),
      );
      canvas.drawCircle(
        blip.position,
        blipRadius * 0.5,
        Paint()..color = blipColor.withValues(alpha: 0.95 * alpha),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TerrainEchoPainter oldDelegate) {
    return oldDelegate.center != center ||
        !identical(oldDelegate.rimPx, rimPx) ||
        oldDelegate.degrees != degrees ||
        oldDelegate.accuracy != accuracy ||
        oldDelegate.sweepT != sweepT ||
        !identical(oldDelegate.blips, blips) ||
        oldDelegate.blipAlphas != blipAlphas;
  }
}
