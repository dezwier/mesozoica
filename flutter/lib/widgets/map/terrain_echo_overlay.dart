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
///
/// Drawn in a ground-plane basis (east/north → screen) so the disc tilts with
/// map pitch in rotate mode. Blips ping when the sweep passes, then fade.
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
  double _prevSweepT = 0;

  Offset? _centerPx;
  Offset _eastPx = Offset.zero;
  Offset _northPx = Offset.zero;
  List<_EchoBlip> _blips = const [];
  final Map<int, double> _blipHitAtMs = {};

  static const _amber = Color(0xFFC4A35A);
  static const _amberBright = Color(0xFFE8C060);
  static const _disc = Color(0xFF140E08);

  /// Blip fade after the sweep hits (seconds).
  static const _blipFadeS = 0.45;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(vsync: this)
      ..addListener(_onSweepTick);
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
    if (mounted) setState(() {});
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
      _projectTimer ??= Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => unawaited(_reproject()),
      );
      unawaited(_reproject());
    } else {
      _projectTimer?.cancel();
      _projectTimer = null;
      _blipHitAtMs.clear();
      if (_centerPx != null || _blips.isNotEmpty) {
        setState(() {
          _centerPx = null;
          _eastPx = Offset.zero;
          _northPx = Offset.zero;
          _blips = const [];
        });
      }
    }
  }

  void _updateBlipHits(double prevT, double currT) {
    if (_blips.isEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    // Leading-edge angles in [0, 1) of a full turn.
    var prev = prevT % 1.0;
    var curr = currT % 1.0;
    if (curr < prev) curr += 1.0; // wrap

    for (final blip in _blips) {
      var hitT = blip.angle / (math.pi * 2);
      hitT = hitT % 1.0;
      if (hitT < 0) hitT += 1.0;
      // Also check +1 for wrap window.
      final hit = hitT;
      final hitWrapped = hitT + 1.0;
      if ((hit > prev && hit <= curr) ||
          (hitWrapped > prev && hitWrapped <= curr)) {
        _blipHitAtMs[blip.siteId] = nowMs;
      }
    }
  }

  Future<void> _reproject() async {
    final echo = _echo;
    if (echo == null || !echo.isActive || !mounted) {
      if (_centerPx != null || _blips.isNotEmpty) {
        setState(() {
          _centerPx = null;
          _eastPx = Offset.zero;
          _northPx = Offset.zero;
          _blips = const [];
        });
      }
      return;
    }

    final origin =
        echo.origin ?? context.read<LocationService>().currentLocation;
    if (origin == null) return;

    final seq = ++_projectSeq;
    final rangeM = echo.rangeM;
    final east = _offsetMeters(origin, eastM: rangeM, northM: 0);
    final north = _offsetMeters(origin, eastM: 0, northM: rangeM);

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
      north,
      for (final s in sitesInRange) LatLng(s.latitude!, s.longitude!),
    ];
    final pixels = await widget.camera.pixelsForCoordinates(points);
    if (!mounted || seq != _projectSeq) return;

    final center = pixels.isNotEmpty ? pixels[0] : null;
    final eastP = pixels.length > 1 ? pixels[1] : null;
    final northP = pixels.length > 2 ? pixels[2] : null;
    if (center == null || eastP == null || northP == null) return;

    final eastVec = eastP - center;
    final northVec = northP - center;
    if (eastVec.distance < 4 || northVec.distance < 4) return;

    final accuracy = echo.accuracy.clamp(0.0, 1.0);
    final blips = <_EchoBlip>[];
    for (var i = 0; i < sitesInRange.length; i++) {
      final px = pixels[i + 3];
      if (px == null) continue;
      final site = sitesInRange[i];
      final unit = _screenToUnit(px - center, eastVec, northVec);
      if (unit == null) continue;
      // Accuracy jitter in unit space (fraction of range).
      final jitterFrac = (1.0 - accuracy) * 0.08;
      final jitter = _stableJitterUnit(site.siteId, jitterFrac);
      final ux = (unit.dx + jitter.dx).clamp(-1.2, 1.2);
      final uy = (unit.dy + jitter.dy).clamp(-1.2, 1.2);
      blips.add(
        _EchoBlip(
          unitX: ux,
          unitY: uy,
          // Unit +y = north; Flutter sweep angles increase toward local +y,
          // so atan2(north, east) matches the leading-edge angle.
          angle: math.atan2(uy, ux),
          siteId: site.siteId,
        ),
      );
    }

    final liveIds = {for (final b in blips) b.siteId};
    _blipHitAtMs.removeWhere((id, _) => !liveIds.contains(id));

    final centerChanged =
        _centerPx == null || (_centerPx! - center).distance > 0.5;
    final basisChanged = (_eastPx - eastVec).distance > 0.5 ||
        (_northPx - northVec).distance > 0.5;
    final blipsChanged =
        _blips.length != blips.length || !_sameBlips(_blips, blips);
    if (!centerChanged && !basisChanged && !blipsChanged) return;

    setState(() {
      _centerPx = center;
      _eastPx = eastVec;
      _northPx = northVec;
      _blips = blips;
    });
  }

  /// Inverse of [east]*x + [north]*y → screen delta.
  static Offset? _screenToUnit(Offset screen, Offset east, Offset north) {
    final det = east.dx * north.dy - east.dy * north.dx;
    if (det.abs() < 1e-6) return null;
    final x = (screen.dx * north.dy - screen.dy * north.dx) / det;
    final y = (east.dx * screen.dy - east.dy * screen.dx) / det;
    return Offset(x, y);
  }

  static bool _sameBlips(List<_EchoBlip> a, List<_EchoBlip> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].siteId != b[i].siteId) return false;
      if ((a[i].unitX - b[i].unitX).abs() > 0.01) return false;
      if ((a[i].unitY - b[i].unitY).abs() > 0.01) return false;
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
    final metersPerDegLon =
        metersPerDegLat * math.cos(latRad).abs().clamp(0.2, 1.0);
    return LatLng(
      origin.latitude + northM / metersPerDegLat,
      origin.longitude + eastM / metersPerDegLon,
    );
  }

  static Offset _stableJitterUnit(int siteId, double frac) {
    if (frac <= 0) return Offset.zero;
    final seed = siteId * 2654435761;
    final a = ((seed >> 16) & 0xffff) / 65535.0;
    final b = (seed & 0xffff) / 65535.0;
    final angle = a * math.pi * 2;
    final dist = b * frac;
    return Offset(math.cos(angle) * dist, math.sin(angle) * dist);
  }

  Map<int, double> _blipAlphas() {
    final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    final fadeMs = _blipFadeS * 1000.0;
    final out = <int, double>{};
    for (final entry in _blipHitAtMs.entries) {
      final age = nowMs - entry.value;
      if (age < 0 || age >= fadeMs) continue;
      // Fast ease-out fade.
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
    if (center == null ||
        _eastPx.distance < 4 ||
        _northPx.distance < 4) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _TerrainEchoPainter(
            center: center,
            eastPx: _eastPx,
            northPx: _northPx,
            rangeM: echo.rangeM,
            ringIncrementM: echo.ringIncrementM,
            degrees: echo.degrees,
            accuracy: echo.accuracy,
            sweepT: _sweep.value,
            blips: _blips,
            blipAlphas: _blipAlphas(),
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
  const _EchoBlip({
    required this.unitX,
    required this.unitY,
    required this.angle,
    required this.siteId,
  });

  /// East/north unit coords (1 = range edge).
  final double unitX;
  final double unitY;
  final double angle;
  final int siteId;
}

class _TerrainEchoPainter extends CustomPainter {
  _TerrainEchoPainter({
    required this.center,
    required this.eastPx,
    required this.northPx,
    required this.rangeM,
    required this.ringIncrementM,
    required this.degrees,
    required this.accuracy,
    required this.sweepT,
    required this.blips,
    required this.blipAlphas,
    required this.amber,
    required this.amberBright,
    required this.disc,
  });

  final Offset center;
  final Offset eastPx;
  final Offset northPx;
  final double rangeM;
  final double ringIncrementM;
  final double degrees;
  final double accuracy;
  final double sweepT;
  final List<_EchoBlip> blips;
  final Map<int, double> blipAlphas;
  final Color amber;
  final Color amberBright;
  final Color disc;

  @override
  void paint(Canvas canvas, Size size) {
    final basis = Matrix4.identity()
      ..setEntry(0, 0, eastPx.dx)
      ..setEntry(1, 0, eastPx.dy)
      ..setEntry(0, 1, northPx.dx)
      ..setEntry(1, 1, northPx.dy)
      ..setEntry(0, 3, center.dx)
      ..setEntry(1, 3, center.dy);

    canvas.save();
    // Ground-plane basis: unit +x = east, +y = north → screen (tilts with pitch).
    canvas.transform(basis.storage);

    // Soft outer fade via radial alpha on the disc.
    final discShader = ui.Gradient.radial(
      Offset.zero,
      1.0,
      [
        disc.withValues(alpha: 0.82),
        disc.withValues(alpha: 0.55),
        disc.withValues(alpha: 0.18),
        disc.withValues(alpha: 0.0),
      ],
      const [0.0, 0.62, 0.88, 1.0],
    );
    canvas.drawCircle(Offset.zero, 1.0, Paint()..shader = discShader);

    final increment = ringIncrementM <= 0 ? 20.0 : ringIncrementM;
    final ringCount = (rangeM / increment).ceil().clamp(1, 20);
    for (var i = 1; i <= ringCount; i++) {
      final r = (i * increment / rangeM).clamp(0.0, 1.0);
      final ringAlpha = ui.lerpDouble(0.55, 0.12, r)!;
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..color = amber.withValues(alpha: ringAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.012 / r.clamp(0.25, 1.0),
      );
    }

    canvas.drawLine(
      const Offset(-1, 0),
      const Offset(1, 0),
      Paint()
        ..color = amber.withValues(alpha: 0.28)
        ..strokeWidth = 0.01,
    );
    canvas.drawLine(
      const Offset(0, -1),
      const Offset(0, 1),
      Paint()
        ..color = amber.withValues(alpha: 0.28)
        ..strokeWidth = 0.01,
    );

    final sweepRad = sweepT * math.pi * 2;
    final wedgeRad = (degrees.clamp(1.0, 360.0) * math.pi / 180.0);
    final start = sweepRad - wedgeRad;

    // Smooth trailing fade (dense stops) — avoids hard ray banding.
    final sweepShader = ui.Gradient.sweep(
      Offset.zero,
      [
        amberBright.withValues(alpha: 0.0),
        amber.withValues(alpha: 0.02),
        amber.withValues(alpha: 0.06),
        amber.withValues(alpha: 0.14),
        amber.withValues(alpha: 0.28),
        amberBright.withValues(alpha: 0.42),
      ],
      const [0.0, 0.2, 0.4, 0.65, 0.85, 1.0],
      TileMode.clamp,
      start,
      sweepRad,
    );
    canvas.drawArc(
      const Rect.fromLTWH(-1, -1, 2, 2),
      start,
      wedgeRad,
      true,
      Paint()..shader = sweepShader,
    );

    // Soft leading edge (thin, low alpha — not a hard ray).
    // Leading edge in Flutter canvas angles (clockwise from +x).
    canvas.drawLine(
      Offset.zero,
      Offset(math.cos(sweepRad), math.sin(sweepRad)),
      Paint()
        ..color = amberBright.withValues(alpha: 0.35)
        ..strokeWidth = 0.014
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(
      Offset.zero,
      1.0,
      Paint()
        ..color = amber.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.018,
    );

    canvas.restore();

    // Blips in screen space so blur stays in pixels (only while fading).
    final scale = (eastPx.distance + northPx.distance) * 0.5;
    final blurSigma = ui.lerpDouble(14.0, 2.0, accuracy.clamp(0.0, 1.0))!;
    final blipRadius =
        ui.lerpDouble(scale * 0.09, scale * 0.035, accuracy.clamp(0.0, 1.0))!;
    for (final blip in blips) {
      final alpha = blipAlphas[blip.siteId] ?? 0.0;
      if (alpha <= 0.01) continue;
      final pos = Offset(
        center.dx + eastPx.dx * blip.unitX + northPx.dx * blip.unitY,
        center.dy + eastPx.dy * blip.unitX + northPx.dy * blip.unitY,
      );
      canvas.drawCircle(
        pos,
        blipRadius * 1.8,
        Paint()
          ..color = amberBright.withValues(alpha: 0.45 * alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma),
      );
      canvas.drawCircle(
        pos,
        blipRadius * 0.55,
        Paint()..color = amberBright.withValues(alpha: 0.95 * alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TerrainEchoPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.eastPx != eastPx ||
        oldDelegate.northPx != northPx ||
        oldDelegate.rangeM != rangeM ||
        oldDelegate.ringIncrementM != ringIncrementM ||
        oldDelegate.degrees != degrees ||
        oldDelegate.accuracy != accuracy ||
        oldDelegate.sweepT != sweepT ||
        oldDelegate.blips != blips ||
        oldDelegate.blipAlphas != blipAlphas;
  }
}
