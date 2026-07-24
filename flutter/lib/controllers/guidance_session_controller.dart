import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../config/game_config.dart';
import '../controllers/field_discovery_coordinator.dart';
import '../models/guidance_tool_kind.dart';
import '../models/site.dart';
import '../models/tool.dart';
import '../services/location_service.dart';
import '../services/tool_service.dart';
import '../utils/guidance_math.dart';

/// Active timed site-guidance session (needle / distance overlays).
class GuidanceSessionController extends ChangeNotifier {
  GuidanceSessionController({ToolService? toolService})
      : _toolService = toolService ?? ToolService();

  final ToolService _toolService;
  final math.Random _random = math.Random();

  FieldDiscoveryCoordinator? _discovery;
  LocationService? _location;
  VoidCallback? _discoveryListener;
  VoidCallback? _locationListener;
  VoidCallback? _headingListener;

  GuidanceSession? _session;
  GuidanceToolKind? _kind;
  ToolSummary? _tool;
  bool _activating = false;
  String? _message;
  bool _requestEnterRotate = false;

  int? _targetSiteId;
  SiteSummary? _targetSite;
  double? _distanceM;
  String? _distanceLabel;
  double _trueBearingDeg = 0;
  double _displayJitterDeg = 0;
  double _jitterFromDeg = 0;
  double _jitterToDeg = 0;
  DateTime? _jitterPeriodStarted;
  bool _showRetargetBadge = false;
  Timer? _badgeTimer;
  Timer? _tickTimer;

  bool get isActive =>
      _session != null && _session!.isActive && !_session!.isExpired;
  GuidanceSession? get session => _session;
  GuidanceToolKind? get kind => _kind;
  ToolSummary? get tool => _tool;
  bool get isActivating => _activating;
  String? get message => _message;
  bool get requestEnterRotate => _requestEnterRotate;

  int? get targetSiteId => _targetSiteId;
  SiteSummary? get targetSite => _targetSite;
  double? get distanceM => _distanceM;
  String? get distanceLabel => _distanceLabel;
  bool get showRetargetBadge => _showRetargetBadge;

  bool get showNeedle => _kind?.showNeedle == true && isActive;
  bool get showDistance => _kind?.showDistance == true && isActive;

  Duration? get remaining {
    final expires = _session?.expiresAt;
    if (expires == null) return null;
    final left = expires.difference(DateTime.now().toUtc());
    return left.isNegative ? Duration.zero : left;
  }

  /// Screen-relative needle angle (0 = device forward).
  double get needleScreenDeg {
    final heading = _location?.headingDeg ?? 0;
    return GuidanceMath.needleScreenDeg(
      trueBearingDeg: _trueBearingDeg,
      deviceHeadingDeg: heading,
      jitterDeg: _displayJitterDeg,
    );
  }

  void bind({
    required FieldDiscoveryCoordinator discovery,
    required LocationService location,
  }) {
    if (_discovery == discovery && _location == location) return;
    _unbindListeners();
    _discovery = discovery;
    _location = location;
    _discoveryListener = _onDiscoveryChanged;
    _locationListener = _onLocationChanged;
    _headingListener = _onHeadingChanged;
    discovery.addListener(_discoveryListener!);
    location.addListener(_locationListener!);
    location.headingListenable.addListener(_headingListener!);
  }

  void consumeEnterRotateRequest() {
    _requestEnterRotate = false;
  }

  Future<void> activate(ToolSummary tool) async {
    if (!tool.isOwned) return;
    final kind = GuidanceToolKind.tryParseToolName(tool.name);
    if (kind == null) return;

    _activating = true;
    _message = null;
    notifyListeners();
    try {
      final session = await _toolService.startGuidanceSession(toolId: tool.id);
      _session = session;
      _kind = GuidanceToolKind.tryParseActionKey(session.actionKey) ?? kind;
      _tool = tool;
      _requestEnterRotate = true;
      _resetJitter();
      _recomputeTarget(announceRetarget: false);
      _ensureTickTimer();
      _message = '${kind.toolName} active';
    } catch (error) {
      _message = error.toString();
    } finally {
      _activating = false;
      notifyListeners();
    }
  }

  Future<void> stop({bool notifyServer = true}) async {
    _badgeTimer?.cancel();
    _tickTimer?.cancel();
    _tickTimer = null;
    _showRetargetBadge = false;
    final hadSession = _session != null;
    if (notifyServer && hadSession) {
      try {
        await _toolService.cancelGuidanceSession();
      } catch (_) {
        // Local stop still clears overlays.
      }
    }
    _session = null;
    _kind = null;
    _tool = null;
    _targetSiteId = null;
    _targetSite = null;
    _distanceM = null;
    _distanceLabel = null;
    if (hadSession) notifyListeners();
  }

  void onRotateModeExited() {
    if (isActive) {
      unawaited(stop());
    }
  }

  void _onDiscoveryChanged() => _recomputeTarget(announceRetarget: true);

  void _onLocationChanged() => _recomputeTarget(announceRetarget: true);

  void _onHeadingChanged() {
    if (!isActive) return;
    _updateJitterInterpolation();
    notifyListeners();
  }

  void _ensureTickTimer() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!isActive) {
        unawaited(stop(notifyServer: false));
        return;
      }
      _updateJitterInterpolation();
      notifyListeners();
    });
  }

  void _resetJitter() {
    final amp = _jitterAmplitude();
    _jitterFromDeg = 0;
    _jitterToDeg = GuidanceMath.sampleJitterDeg(
      amplitudeDeg: amp,
      random: _random,
    );
    _jitterPeriodStarted = DateTime.now();
    _displayJitterDeg = _jitterFromDeg;
  }

  double _jitterAmplitude() {
    final cfg = _kind?.config(GameConfig.instance);
    final exactness = _session?.directionExactness ??
        cfg?.resolvedDirectionExactness ??
        0.0;
    final maxJitter = cfg?.maxJitterDeg ?? 90.0;
    return GuidanceMath.jitterAmplitudeDeg(
      exactness: exactness,
      maxJitterDeg: maxJitter,
    );
  }

  void _updateJitterInterpolation() {
    if (!showNeedle) {
      _displayJitterDeg = 0;
      return;
    }
    final cfg = _kind?.config(GameConfig.instance);
    final periodS = cfg?.needleJitterPeriodS ?? 3.0;
    final periodMs = (periodS * 1000).clamp(200, 60000).toInt();
    final started = _jitterPeriodStarted ?? DateTime.now();
    final elapsed = DateTime.now().difference(started).inMilliseconds;
    if (elapsed >= periodMs) {
      _jitterFromDeg = _jitterToDeg;
      _jitterToDeg = GuidanceMath.sampleJitterDeg(
        amplitudeDeg: _jitterAmplitude(),
        random: _random,
      );
      _jitterPeriodStarted = DateTime.now();
      _displayJitterDeg = _jitterFromDeg;
      return;
    }
    final t = elapsed / periodMs;
    _displayJitterDeg = GuidanceMath.lerpJitterDeg(
      fromDeg: _jitterFromDeg,
      toDeg: _jitterToDeg,
      t: t,
    );
  }

  void _recomputeTarget({required bool announceRetarget}) {
    if (!isActive) return;
    final discovery = _discovery;
    final location = _location?.currentLocation;
    if (discovery == null || location == null) {
      _clearTarget();
      notifyListeners();
      return;
    }

    final nearest = discovery.nearestDiscoverable(location);
    final previousId = _targetSiteId;
    if (nearest == null) {
      _clearTarget();
      notifyListeners();
      return;
    }

    final site = nearest.site;
    final distM = nearest.distanceM;
    _targetSiteId = site.siteId;
    _targetSite = site;
    _distanceM = distM;
    _trueBearingDeg = Geolocator.bearingBetween(
      location.latitude,
      location.longitude,
      site.latitude!,
      site.longitude!,
    );

    if (showDistance) {
      final cfg = _kind!.config(GameConfig.instance);
      final exactness =
          _session?.distanceExactness ?? cfg.resolvedDistanceExactness;
      _distanceLabel = GuidanceMath.formatDistance(
        distanceM: distM,
        exactness: exactness,
        bandEdgesM: cfg.bandEdgesM,
        midRoundM: cfg.midRoundM,
      );
    } else {
      _distanceLabel = null;
    }

    _updateJitterInterpolation();

    if (announceRetarget &&
        previousId != null &&
        previousId != site.siteId) {
      _flashRetargetBadge();
    }
    notifyListeners();
  }

  void _clearTarget() {
    _targetSiteId = null;
    _targetSite = null;
    _distanceM = null;
    _distanceLabel = null;
  }

  void _flashRetargetBadge() {
    _showRetargetBadge = true;
    _badgeTimer?.cancel();
    _badgeTimer = Timer(const Duration(seconds: 3), () {
      _showRetargetBadge = false;
      notifyListeners();
    });
  }

  void _unbindListeners() {
    if (_discovery != null && _discoveryListener != null) {
      _discovery!.removeListener(_discoveryListener!);
    }
    if (_location != null) {
      if (_locationListener != null) {
        _location!.removeListener(_locationListener!);
      }
      if (_headingListener != null) {
        _location!.headingListenable.removeListener(_headingListener!);
      }
    }
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    _tickTimer?.cancel();
    _unbindListeners();
    super.dispose();
  }
}
