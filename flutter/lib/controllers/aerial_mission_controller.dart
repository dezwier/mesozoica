import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../config/game_config.dart';
import '../models/aerial_mission_kind.dart';
import '../models/tool.dart';
import '../services/tool_service.dart';
import '../utils/route_geometry.dart';

/// Client state for aerial mission draw mode, submit, and map tracking.
class AerialMissionController extends ChangeNotifier {
  AerialMissionController({ToolService? toolService})
      : _toolService = toolService ?? ToolService();

  final ToolService _toolService;
  final Distance _distance = const Distance();

  bool _drawMode = false;
  ToolSummary? _tool;
  final List<LatLng> _route = [];
  bool _drawing = false;
  bool _submitting = false;
  String? _message;

  List<AerialMission> _missions = const [];
  bool _missionsLoading = false;
  /// True while the map tab wants mission tracking (see [startTracking]).
  bool _mapTracking = false;
  Timer? _refreshTimer;
  Timer? _progressTimer;
  /// Bumps only after a successful missions list fetch (not progress ticks).
  int _missionsFetchGeneration = 0;
  AerialMission? _focusedMission;
  AerialMission? _pendingFocusMission;
  /// One-shot: MapScreen should fit the viewport to [maxRouteKm] on draw entry.
  bool _pendingDrawCamera = false;

  bool get isDrawMode => _drawMode;
  ToolSummary? get tool => _tool;
  List<LatLng> get route => List.unmodifiable(_route);
  bool get isDrawing => _drawing;
  bool get isSubmitting => _submitting;
  String? get message => _message;
  bool get hasRoute => _route.length >= 2;

  List<AerialMission> get missions => List.unmodifiable(_missions);
  bool get missionsLoading => _missionsLoading;
  AerialMission? get focusedMission => _focusedMission;
  AerialMission? get pendingFocusMission => _pendingFocusMission;
  bool get pendingDrawCamera => _pendingDrawCamera;

  /// Bumps while any flying mission is active so map layers can re-interpolate.
  /// Prefer [progressTickListenable] for UI — progress ticks do not call
  /// [notifyListeners].
  int get progressTick => progressTickListenable.value;

  /// Flying scout interpolation tick (~4 Hz) without rebuilding Provider trees.
  final ValueNotifier<int> progressTickListenable = ValueNotifier<int>(0);

  /// Increments when missions are reloaded from the server.
  int get missionsFetchGeneration => _missionsFetchGeneration;

  AerialMissionKind get drawKind =>
      AerialMissionKind.tryParseToolName(_tool?.name) ?? AerialMissionKind.recon;

  AerialMissionActionConfig get _cfg =>
      drawKind.config(GameConfig.instance);

  Map<String, dynamic> get _toolParams {
    final tool = _tool;
    if (tool == null) return const {};
    if (tool.isOwned && tool.params.isNotEmpty) return tool.params;
    return tool.baseParams;
  }

  int get durationMinutes =>
      (_toolParams['duration_minutes'] as num?)?.toInt() ?? _cfg.durationMinutes;

  double get flightSpeedKmh =>
      (_toolParams['flight_speed_kmh'] as num?)?.toDouble() ??
      _cfg.flightSpeedKmh;

  /// Draw/deploy limit from speed × duration.
  double get maxRouteKm => flightSpeedKmh * durationMinutes / 60.0;

  double get loopEndpointToleranceM =>
      (_toolParams['loop_endpoint_tolerance_m'] as num?)?.toDouble() ??
      _cfg.loopEndpointToleranceM;

  double get shortRouteWarnFraction =>
      (_toolParams['short_route_warn_fraction'] as num?)?.toDouble() ??
      _cfg.shortRouteWarnFraction;

  double routeLengthKm() {
    if (_route.length < 2) return 0;
    var metres = 0.0;
    for (var i = 1; i < _route.length; i++) {
      metres += _distance(_route[i - 1], _route[i]);
    }
    return metres / 1000.0;
  }

  bool get isShortRoute {
    if (maxRouteKm <= 0) return false;
    return routeLengthKm() < maxRouteKm * shortRouteWarnFraction;
  }

  String get rangeHint {
    final budget =
        '${_formatDuration(durationMinutes)} at ${_formatKmh(flightSpeedKmh)}';
    final drawn = routeLengthKm();
    if (drawn <= 0) {
      return 'Allowed range: up to ${_formatKm(maxRouteKm)} ($budget)';
    }
    return 'Drawn ${drawn.toStringAsFixed(1)} km · '
        'allowed up to ${_formatKm(maxRouteKm)} ($budget)';
  }

  String _allowedRangeMessage() {
    return 'Allowed range: up to ${_formatKm(maxRouteKm)} '
        '(${_formatDuration(durationMinutes)} at ${_formatKmh(flightSpeedKmh)})';
  }

  String _drawIntroMessage() {
    return 'Draw with one finger; pinch to zoom. '
        'The loop starts and ends at your location. '
        '${_allowedRangeMessage()}.';
  }

  /// Scout position for [mission] at [now] (UTC).
  LatLng? scoutPosition(AerialMission mission, {DateTime? now}) {
    if (mission.route.isEmpty) return null;
    final frac = aerialMissionProgressFraction(mission, now: now);
    return RouteGeometry.pointAtFraction(mission.route, frac);
  }

  double scoutBearing(AerialMission mission, {DateTime? now}) {
    if (mission.route.length < 2) return 0;
    final frac = aerialMissionProgressFraction(mission, now: now);
    return RouteGeometry.bearingAtFraction(mission.route, frac);
  }

  void beginDraw(ToolSummary tool) {
    _tool = tool;
    _drawMode = true;
    _route.clear();
    _drawing = false;
    _submitting = false;
    _pendingDrawCamera = true;
    _message = _drawIntroMessage();
    notifyListeners();
  }

  void cancelDraw() {
    _drawMode = false;
    _tool = null;
    _route.clear();
    _drawing = false;
    _submitting = false;
    _pendingDrawCamera = false;
    _message = null;
    notifyListeners();
  }

  void clearRoute({String? message}) {
    _route.clear();
    _drawing = false;
    _message = message;
    notifyListeners();
  }

  /// Reset the drawn route; stay in draw mode.
  void clearDrawnRoute() {
    if (!_drawMode || _submitting) return;
    _route.clear();
    _drawing = false;
    _message = _drawIntroMessage();
    notifyListeners();
  }

  /// Pause an in-progress stroke without clearing or closing it (e.g. pinch).
  void pauseStroke() {
    if (!_drawing) return;
    _drawing = false;
    notifyListeners();
  }

  /// Resume appending to an existing unfinished stroke after a pinch.
  void resumeStroke() {
    if (!_drawMode || _submitting) return;
    if (_route.isEmpty) return;
    _drawing = true;
    _message = null;
    notifyListeners();
  }

  /// Begin a stroke anchored at [origin] (current location).
  void startStroke(LatLng fingerPoint, {required LatLng? origin}) {
    if (!_drawMode || _submitting) return;
    if (origin == null) {
      _message = 'Waiting for your current location';
      notifyListeners();
      return;
    }
    _route
      ..clear()
      ..add(origin);
    if (_distance(origin, fingerPoint) >= 25) {
      _route.add(fingerPoint);
    }
    _drawing = true;
    _message = null;
    notifyListeners();
  }

  void appendPoint(LatLng point, {double minSpacingM = 25}) {
    if (!_drawMode || !_drawing || _submitting) return;
    if (_route.isEmpty) {
      _route.add(point);
      notifyListeners();
      return;
    }
    final last = _route.last;
    if (_distance(last, point) < minSpacingM) return;
    _route.add(point);
    notifyListeners();
  }

  /// End stroke and snap the route closed on [origin].
  void endStroke({LatLng? origin}) {
    if (!_drawing) return;
    if (origin != null) {
      _snapEndpointsToOrigin(origin);
    }
    _drawing = false;
    notifyListeners();
  }

  /// Returns an error message, or null when the route is valid.
  String? validationError(LatLng? origin) {
    if (origin == null) {
      return 'Waiting for your current location';
    }
    if (_route.length < 3) {
      return 'Draw a longer loop, then tap ${drawKind.deployVerb}';
    }

    final lengthKm = routeLengthKm();
    if (lengthKm > maxRouteKm) {
      return 'Loop was ${lengthKm.toStringAsFixed(1)} km; '
          'maximum allowed is ${_formatKm(maxRouteKm)}.';
    }
    return null;
  }

  /// Validate and submit the aerial mission.
  Future<bool> deployMission({required LatLng origin}) async {
    final tool = _tool;
    if (tool == null || !_drawMode || _submitting) return false;
    final kind = drawKind;

    _snapEndpointsToOrigin(origin);
    _drawing = false;

    final error = validationError(origin);
    if (error != null) {
      clearRoute(message: error);
      return false;
    }

    _submitting = true;
    _message = '${kind.deployVerb}ing ${kind.toolName}…';
    notifyListeners();

    try {
      final mission = await _toolService.startAerialMission(
        toolId: tool.id,
        route: List<LatLng>.from(_route),
        origin: origin,
      );
      _upsertMission(mission);
      cancelDraw();
      unawaited(refreshMissions());
      return true;
    } on ToolServiceException catch (error) {
      _message = error.message;
      _submitting = false;
      notifyListeners();
      return false;
    } catch (_) {
      _message = 'Failed to ${kind.deployVerb.toLowerCase()} ${kind.toolName}';
      _submitting = false;
      notifyListeners();
      return false;
    }
  }

  /// Select a mission for the map overlay and queue a one-shot camera focus.
  void focusMission(AerialMission mission) {
    _focusedMission = mission;
    _pendingFocusMission = mission;
    _syncMissionTimers();
    notifyListeners();
  }

  /// Resolve [missionId] from cached missions (refreshing if needed) and focus.
  Future<bool> focusMissionById(int missionId) async {
    AerialMission? match;
    for (final m in _missions) {
      if (m.missionId == missionId) {
        match = m;
        break;
      }
    }
    if (match == null) {
      await refreshMissions();
      for (final m in _missions) {
        if (m.missionId == missionId) {
          match = m;
          break;
        }
      }
    }
    if (match == null) return false;
    focusMission(match);
    return true;
  }

  void clearFocus() {
    if (_focusedMission == null && _pendingFocusMission == null) return;
    _focusedMission = null;
    _pendingFocusMission = null;
    _syncMissionTimers();
    notifyListeners();
  }

  /// Cancel an active mission; keeps focus on the truncated cancelled route.
  Future<bool> cancelMission(int missionId) async {
    try {
      final mission = await _toolService.cancelAerialMission(missionId);
      if (_focusedMission?.missionId == missionId) {
        _focusedMission = mission;
      }
      _upsertMission(mission);
      return true;
    } on ToolServiceException catch (error) {
      _message = error.message;
      notifyListeners();
      return false;
    } catch (_) {
      _message = 'Failed to cancel Aerial Recon';
      notifyListeners();
      return false;
    }
  }

  /// One-shot camera request; cleared when MapScreen consumes it.
  AerialMission? takePendingFocusMission() {
    final mission = _pendingFocusMission;
    _pendingFocusMission = null;
    return mission;
  }

  /// One-shot draw-entry camera fit; cleared when MapScreen consumes it.
  bool takePendingDrawCamera() {
    if (!_pendingDrawCamera) return false;
    _pendingDrawCamera = false;
    return true;
  }

  /// Load missions from the server (cross-device). Call when map becomes active.
  Future<void> refreshMissions() async {
    if (_missionsLoading) return;
    _missionsLoading = true;
    notifyListeners();
    try {
      final items = await _toolService.fetchAerialMissions();
      _missions = items;
      _missionsFetchGeneration++;
      final focusedId = _focusedMission?.missionId;
      if (focusedId != null) {
        AerialMission? match;
        for (final m in items) {
          if (m.missionId == focusedId) {
            match = m;
            break;
          }
        }
        if (match != null) _focusedMission = match;
      }
      _syncMissionTimers();
      notifyListeners();
    } on ToolServiceException catch (error) {
      if (kDebugMode) {
        debugPrint('AerialMission refresh failed: $error');
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('AerialMission refresh failed: $error');
      }
    } finally {
      _missionsLoading = false;
      notifyListeners();
    }
  }

  /// One-shot fetch when map tracking first enables; poll only while flying/ensuring.
  ///
  /// Idempotent: parent rebuilds must not re-hit the network.
  void startTracking() {
    if (_mapTracking) {
      _syncMissionTimers();
      return;
    }
    _mapTracking = true;
    unawaited(refreshMissions());
    _syncMissionTimers();
  }

  void stopTracking() {
    _mapTracking = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void _upsertMission(AerialMission mission) {
    final next = [
      mission,
      for (final existing in _missions)
        if (existing.missionId != mission.missionId) existing,
    ];
    _missions = next;
    _syncMissionTimers();
    notifyListeners();
  }

  bool get _hasActiveMission =>
      _missions.any((m) => m.isActive) ||
      (_focusedMission?.isActive ?? false);

  void _syncMissionTimers() {
    _syncRefreshTimer();
    _syncProgressTimer();
  }

  /// Poll server (~5s) only while map tracking and a mission is ensuring/flying.
  void _syncRefreshTimer() {
    if (!_mapTracking || !_hasActiveMission) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      return;
    }
    _refreshTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(refreshMissions());
    });
  }

  void _syncProgressTimer() {
    final needsTick = _missions.any((m) => m.isFlying) ||
        (_focusedMission?.isFlying ?? false);
    if (needsTick) {
      // ~4 Hz keeps the scout puck moving smoothly without thrashing Mapbox.
      _progressTimer ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
        progressTickListenable.value = progressTickListenable.value + 1;
      });
    } else {
      _progressTimer?.cancel();
      _progressTimer = null;
    }
  }

  void _snapEndpointsToOrigin(LatLng origin) {
    if (_route.isEmpty) {
      _route.add(origin);
      return;
    }
    _route[0] = origin;
    if (_route.length == 1) {
      return;
    }
    if (_distance(_route.last, origin) < 5) {
      _route[_route.length - 1] = origin;
    } else {
      _route.add(origin);
    }
  }

  static String _formatKm(double km) {
    if (km == km.roundToDouble()) return '${km.toStringAsFixed(0)} km';
    return '${km.toStringAsFixed(1)} km';
  }

  static String _formatKmh(double kmh) {
    if (kmh == kmh.roundToDouble()) return '${kmh.toStringAsFixed(0)} km/h';
    return '${kmh.toStringAsFixed(1)} km/h';
  }

  static String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rem = minutes % 60;
    if (rem == 0) return hours == 1 ? '1 hour' : '$hours hours';
    return '${hours}h ${rem}m';
  }

  @override
  void dispose() {
    stopTracking();
    progressTickListenable.dispose();
    super.dispose();
  }
}
