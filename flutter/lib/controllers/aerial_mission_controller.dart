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
  Timer? _refreshTimer;
  Timer? _progressTimer;
  int _progressTick = 0;
  /// Bumps only after a successful missions list fetch (not progress ticks).
  int _missionsFetchGeneration = 0;
  AerialMission? _focusedMission;
  AerialMission? _pendingFocusMission;

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

  /// Bumps while any flying mission is active so map layers can re-interpolate.
  int get progressTick => _progressTick;

  /// Increments when missions are reloaded from the server.
  int get missionsFetchGeneration => _missionsFetchGeneration;

  AerialMissionKind get drawKind =>
      AerialMissionKind.tryParseToolName(_tool?.name) ?? AerialMissionKind.recon;

  AerialMissionActionConfig get _cfg =>
      drawKind.config(GameConfig.instance);

  double get maxRouteKm => _cfg.maxRouteKm;
  double get loopEndpointToleranceM => _cfg.loopEndpointToleranceM;
  double get shortRouteWarnFraction => _cfg.shortRouteWarnFraction;

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
    final maxLabel = maxRouteKm == maxRouteKm.roundToDouble()
        ? maxRouteKm.toStringAsFixed(0)
        : maxRouteKm.toStringAsFixed(1);
    final drawn = routeLengthKm();
    if (drawn <= 0) {
      return 'Allowed range: up to $maxLabel km';
    }
    return 'Drawn ${drawn.toStringAsFixed(1)} km · allowed up to $maxLabel km';
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
    _message =
        'Draw with one finger; pinch to zoom. '
        'The loop starts and ends at your location. '
        'Allowed range: up to ${_formatKm(maxRouteKm)}.';
    notifyListeners();
  }

  void cancelDraw() {
    _drawMode = false;
    _tool = null;
    _route.clear();
    _drawing = false;
    _submitting = false;
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
    _message =
        'Draw with one finger; pinch to zoom. '
        'The loop starts and ends at your location. '
        'Allowed range: up to ${_formatKm(maxRouteKm)}.';
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
    _syncProgressTimer();
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
    _syncProgressTimer();
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
      _syncProgressTimer();
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

  /// Start periodic status refresh (~5s) while the map is active.
  void startTracking() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(refreshMissions());
    });
    unawaited(refreshMissions());
    _syncProgressTimer();
  }

  void stopTracking() {
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
    _syncProgressTimer();
    notifyListeners();
  }

  void _syncProgressTimer() {
    final needsTick = _missions.any((m) => m.isFlying) ||
        (_focusedMission?.isFlying ?? false);
    if (needsTick) {
      // ~4 Hz keeps the scout puck moving smoothly without thrashing Mapbox.
      _progressTimer ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
        _progressTick++;
        notifyListeners();
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

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}
