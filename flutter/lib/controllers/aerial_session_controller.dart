import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../config/game_config.dart';
import '../models/aerial_action_kind.dart';
import '../models/site_map_filters.dart';
import '../models/tool.dart';
import '../models/tool_session.dart';
import '../services/tool_service.dart';
import '../utils/route_geometry.dart';

/// Client state for aerial session draw mode, submit, and map tracking.
class AerialSessionController extends ChangeNotifier {
  AerialSessionController({ToolService? toolService})
      : _toolService = toolService ?? ToolService();

  final ToolService _toolService;
  final Distance _distance = const Distance();

  bool _drawMode = false;
  ToolSummary? _tool;
  final List<LatLng> _route = [];
  bool _drawing = false;
  bool _submitting = false;
  String? _message;

  List<ToolSession> _sessions = const [];
  bool _sessionsLoading = false;
  /// True while the map tab wants session tracking (see [startTracking]).
  bool _mapTracking = false;
  Timer? _refreshTimer;
  Timer? _progressTimer;
  /// Bumps only after a successful sessions list fetch (not progress ticks).
  int _sessionsFetchGeneration = 0;
  ToolSession? _focusedSession;
  ToolSession? _pendingFocusSession;
  /// One-shot: MapScreen should fit the viewport to [maxRouteKm] on draw entry.
  bool _pendingDrawCamera = false;

  bool get isDrawMode => _drawMode;
  ToolSummary? get tool => _tool;
  List<LatLng> get route => List.unmodifiable(_route);
  bool get isDrawing => _drawing;
  bool get isSubmitting => _submitting;
  String? get message => _message;
  bool get hasRoute => _route.length >= 2;

  List<ToolSession> get sessions => List.unmodifiable(_sessions);
  bool get sessionsLoading => _sessionsLoading;
  ToolSession? get focusedSession => _focusedSession;
  ToolSession? get pendingFocusSession => _pendingFocusSession;
  bool get pendingDrawCamera => _pendingDrawCamera;

  /// Session shown on the map HUD: focused live flight, else first live flight.
  ///
  /// Past / arrived / aborted sessions never keep the HUD up.
  ToolSession? get hudSession {
    final focused = _focusedSession;
    if (focused != null && _sessionShowsHud(focused)) return focused;
    for (final s in _sessions) {
      if (_sessionShowsHud(s)) return s;
    }
    return null;
  }

  /// True while the craft is still preparing or in flight (not arrived/aborted).
  bool _sessionShowsHud(ToolSession session) {
    if (session.isPast) return false;
    if (session.isPending) return true;
    if (!session.isInFlight) return false;
    final ends = session.flightEndsAt;
    if (ends == null) return true;
    return DateTime.now().toUtc().isBefore(ends);
  }

  /// Bumps while any flying session is active so map layers can re-interpolate.
  /// Prefer [progressTickListenable] for UI — progress ticks do not call
  /// [notifyListeners].
  int get progressTick => progressTickListenable.value;

  /// Flying scout interpolation tick (~4 Hz) without rebuilding Provider trees.
  final ValueNotifier<int> progressTickListenable = ValueNotifier<int>(0);

  /// Remaining flight time for [hudSession] (null while pending / unknown).
  final ValueNotifier<Duration?> remainingListenable =
      ValueNotifier<Duration?>(null);

  /// Increments when sessions are reloaded from the server.
  int get sessionsFetchGeneration => _sessionsFetchGeneration;

  AerialActionKind get drawKind =>
      AerialActionKind.tryParseToolName(_tool?.name) ?? AerialActionKind.recon;

  AerialActionConfig get _cfg =>
      drawKind.config(GameConfig.instance);

  Map<String, dynamic> get _toolParams {
    final tool = _tool;
    if (tool == null) return const {};
    if (tool.isOwned && tool.params.isNotEmpty) return tool.params;
    return tool.baseParams;
  }

  int get durationMinutes {
    final remainingS = _tool?.remainingDurationS;
    if (remainingS != null) {
      return (remainingS / 60).ceil().clamp(0, 24 * 60);
    }
    return (_toolParams['duration_minutes'] as num?)?.toInt() ??
        _cfg.durationMinutes;
  }

  double get flightSpeedKmh =>
      (_toolParams['flight_speed_kmh'] as num?)?.toDouble() ??
      _cfg.flightSpeedKmh;

  /// Draw/deploy limit from speed × remaining battery.
  double get maxRouteKm {
    final remainingS = _tool?.remainingDurationS;
    if (remainingS != null) {
      return flightSpeedKmh * remainingS / 3600.0;
    }
    return flightSpeedKmh * durationMinutes / 60.0;
  }

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

  /// Scout position for [session] at [now] (UTC).
  LatLng? scoutPosition(ToolSession session, {DateTime? now}) {
    if (session.route.isEmpty) return null;
    final frac = aerialSessionProgressFraction(session, now: now);
    return RouteGeometry.pointAtFraction(session.route, frac);
  }

  double scoutBearing(ToolSession session, {DateTime? now}) {
    if (session.route.length < 2) return 0;
    final frac = aerialSessionProgressFraction(session, now: now);
    return RouteGeometry.bearingAtFraction(session.route, frac);
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

  /// Drop all local session state (e.g. after admin field purge).
  void clearAllLocalSessions() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _progressTimer?.cancel();
    _progressTimer = null;
    _sessions = const [];
    _focusedSession = null;
    _pendingFocusSession = null;
    _sessionsFetchGeneration++;
    remainingListenable.value = null;
    clearRoute();
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

  /// Validate and submit the aerial session.
  Future<bool> deploySession({required LatLng origin}) async {
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
      final session = await _toolService.startToolSession(
        toolId: tool.id,
        route: List<LatLng>.from(_route),
        origin: origin,
      );
      _upsertSession(session);
      cancelDraw();
      unawaited(refreshSessions());
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

  /// Select a session for the map overlay and queue a one-shot camera focus.
  void focusSession(ToolSession session) {
    _focusedSession = session;
    _pendingFocusSession = session;
    _syncSessionTimers();
    notifyListeners();
  }

  /// Resolve [sessionId] from cached sessions (refreshing if needed) and focus.
  Future<bool> focusSessionById(int sessionId) async {
    ToolSession? match;
    for (final s in _sessions) {
      if (s.sessionId == sessionId) {
        match = s;
        break;
      }
    }
    if (match == null) {
      await refreshSessions();
      for (final s in _sessions) {
        if (s.sessionId == sessionId) {
          match = s;
          break;
        }
      }
    }
    if (match == null) {
      try {
        final fetched = await _toolService.fetchSession(sessionId);
        if (!AerialActionKind.isAerialActionKey(fetched.actionKey)) {
          return false;
        }
        _upsertSession(fetched);
        match = fetched;
      } catch (_) {
        return false;
      }
    }
    focusSession(match);
    return true;
  }

  void clearFocus() {
    if (_focusedSession == null && _pendingFocusSession == null) return;
    _focusedSession = null;
    _pendingFocusSession = null;
    _syncSessionTimers();
    notifyListeners();
  }

  /// Cancel an active session and dismiss the HUD.
  Future<bool> cancelSession(int sessionId) async {
    try {
      final session = await _toolService.cancelSession(sessionId);
      if (_focusedSession?.sessionId == sessionId ||
          _pendingFocusSession?.sessionId == sessionId) {
        _focusedSession = null;
        _pendingFocusSession = null;
      }
      _upsertSession(session);
      return true;
    } on ToolServiceException catch (error) {
      _message = error.message;
      notifyListeners();
      return false;
    } catch (_) {
      _message = 'Failed to cancel aerial session';
      notifyListeners();
      return false;
    }
  }

  /// One-shot camera request; cleared when MapScreen consumes it.
  ToolSession? takePendingFocusSession() {
    final session = _pendingFocusSession;
    _pendingFocusSession = null;
    return session;
  }

  /// One-shot draw-entry camera fit; cleared when MapScreen consumes it.
  bool takePendingDrawCamera() {
    if (!_pendingDrawCamera) return false;
    _pendingDrawCamera = false;
    return true;
  }

  /// Load live aerial sessions (and retain recent past routes for the map).
  Future<void> refreshSessions() async {
    if (_sessionsLoading) return;
    _sessionsLoading = true;
    notifyListeners();
    try {
      final live = await _toolService.fetchActiveSessions();
      final aerialLive = [
        for (final s in live)
          if (AerialActionKind.isAerialActionKey(s.actionKey)) s,
      ];
      final now = DateTime.now().toUtc();
      final retainedPast = <ToolSession>[];
      for (final existing in _sessions) {
        if (!existing.isPast) continue;
        if (!AerialActionKind.isAerialActionKey(existing.actionKey)) continue;
        if (aerialLive.any((s) => s.sessionId == existing.sessionId)) {
          continue;
        }
        if (_pastAerialRouteIsRecent(existing, now)) {
          retainedPast.add(existing);
        }
      }
      // Sessions that vanished from live while still "active" locally → keep
      // if they look finished (flight end passed) so the past route remains.
      for (final existing in _sessions) {
        if (!existing.isActive) continue;
        if (aerialLive.any((s) => s.sessionId == existing.sessionId)) {
          continue;
        }
        final ends = existing.flightEndsAt;
        if (ends != null && !now.isBefore(ends)) {
          retainedPast.add(existing);
        }
      }
      _sessions = [...aerialLive, ...retainedPast];
      _sessionsFetchGeneration++;
      final focusedId = _focusedSession?.sessionId;
      if (focusedId != null) {
        ToolSession? match;
        for (final s in _sessions) {
          if (s.sessionId == focusedId) {
            match = s;
            break;
          }
        }
        if (match != null && _sessionShowsHud(match)) {
          _focusedSession = match;
        } else {
          _focusedSession = null;
          _pendingFocusSession = null;
        }
      }
      _syncSessionTimers();
      notifyListeners();
    } on ToolServiceException catch (error) {
      if (kDebugMode) {
        debugPrint('AerialSession refresh failed: $error');
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('AerialSession refresh failed: $error');
      }
    } finally {
      _sessionsLoading = false;
      notifyListeners();
    }
  }

  bool _pastAerialRouteIsRecent(ToolSession session, DateTime now) {
    final end = session.flightEndsAt ?? session.endedAt ?? session.startedAt;
    return now.difference(end) <= pastAerialRouteMaxAge;
  }

  /// One-shot fetch when map tracking first enables; poll only while live.
  ///
  /// Idempotent: parent rebuilds must not re-hit the network.
  void startTracking() {
    if (_mapTracking) {
      _syncSessionTimers();
      return;
    }
    _mapTracking = true;
    unawaited(refreshSessions());
    _syncSessionTimers();
  }

  void stopTracking() {
    _mapTracking = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void _upsertSession(ToolSession session) {
    final next = [
      session,
      for (final existing in _sessions)
        if (existing.sessionId != session.sessionId) existing,
    ];
    _sessions = next;
    _syncSessionTimers();
    notifyListeners();
  }

  bool get _hasActiveSession =>
      _sessions.any((s) => s.isActive) ||
      (_focusedSession?.isActive ?? false);

  void _syncSessionTimers() {
    _syncRefreshTimer();
    _syncProgressTimer();
    _syncRemaining();
  }

  void _syncRemaining() {
    _dismissHudIfFlightFinished();
    final session = hudSession;
    Duration? next;
    if (session != null && session.isInFlight && session.flightEndsAt != null) {
      final left = session.flightEndsAt!.difference(DateTime.now().toUtc());
      next = left.isNegative ? Duration.zero : left;
    }
    if (remainingListenable.value != next) {
      remainingListenable.value = next;
    }
  }

  /// Drop focus when the focused craft has arrived (or session is otherwise done).
  void _dismissHudIfFlightFinished() {
    final focused = _focusedSession;
    if (focused == null) return;
    if (_sessionShowsHud(focused)) return;
    clearFocus();
  }

  /// Poll server (~5s) only while map tracking and a session is pending/active.
  void _syncRefreshTimer() {
    if (!_mapTracking || !_hasActiveSession) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      return;
    }
    _refreshTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(refreshSessions());
    });
  }

  void _syncProgressTimer() {
    final needsTick = _sessions.any((s) => s.isInFlight) ||
        (_focusedSession?.isInFlight ?? false);
    if (needsTick) {
      // ~4 Hz keeps the scout puck moving smoothly without thrashing Mapbox.
      _progressTimer ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
        progressTickListenable.value = progressTickListenable.value + 1;
        _syncRemaining();
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
    remainingListenable.dispose();
    super.dispose();
  }
}
