import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/main_param_buff_kind.dart';
import '../models/tool.dart';
import '../models/tool_session.dart';
import '../services/tool_service.dart';
import 'timed_session_remaining.dart';

/// Active timed global main-param buff (Ridge Glass / Drivetrain / Nocturne).
///
/// Sessions are mutually exclusive server-side, so one controller covers all
/// members of the buff family.
class MainParamBuffController extends ChangeNotifier {
  MainParamBuffController({ToolService? toolService})
      : _toolService = toolService ?? ToolService();

  final ToolService _toolService;

  ToolSession? _session;
  ToolSummary? _tool;
  MainParamBuffKind? _kind;
  bool _activating = false;
  String? _message;
  bool _requestShowOnMap = false;
  Timer? _tickTimer;

  /// Countdown for HUD / tool cards — does not trigger [notifyListeners].
  final ValueNotifier<Duration?> remainingListenable =
      ValueNotifier<Duration?>(null);

  bool get isActive =>
      _session != null && _session!.isActive && !_session!.isExpired;
  ToolSession? get session => _session;
  ToolSummary? get tool => _tool;
  MainParamBuffKind? get kind => _kind;
  bool get isActivating => _activating;
  String? get message => _message;
  bool get requestShowOnMap => _requestShowOnMap;

  Duration? get remaining => remainingListenable.value;

  bool get isRidgeGlassActive =>
      isActive && _kind?.actionKey == MainParamBuffKind.ridgeGlass.actionKey;

  bool get isExpeditionDrivetrainActive =>
      isActive &&
      _kind?.actionKey == MainParamBuffKind.expeditionDrivetrain.actionKey;

  bool get isNocturneLensActive =>
      isActive && _kind?.actionKey == MainParamBuffKind.nocturneLens.actionKey;

  /// Snapshotted period gate from the live session, or null if unrestricted.
  List<String>? get activeWeatherTimes {
    final raw = _session?.params['active_weather_times'];
    if (raw is! List) return null;
    return raw.map((e) => e.toString()).toList();
  }

  bool isLiveForWeatherTime(String? weatherTime) {
    final allowed = activeWeatherTimes;
    if (allowed == null) return true;
    if (weatherTime == null) return false;
    return allowed.contains(weatherTime);
  }

  Future<void> restoreActiveSession() async {
    if (_activating) return;
    try {
      ToolSession? session;
      MainParamBuffKind? kind;
      for (final candidate in MainParamBuffKind.all) {
        final found = await _toolService.fetchActiveSession(
          actionKey: candidate.actionKey,
        );
        if (found != null && found.isActive && !found.isExpired) {
          session = found;
          kind = candidate;
          break;
        }
      }
      if (session == null || kind == null) {
        if (_session != null && !isActive) {
          await stop(notifyServer: false);
        }
        return;
      }
      if (_session?.sessionId == session.sessionId && isActive) {
        _session = session;
        _kind = kind;
        _ensureTickTimer();
        return;
      }
      _session = session;
      _kind = kind;
      _tool = null;
      _ensureTickTimer();
      _message = '${kind.toolName} active';
      notifyListeners();
    } catch (error) {
      debugPrint('Main-param buff restore failed: $error');
    }
  }

  void consumeShowOnMapRequest() {
    _requestShowOnMap = false;
  }

  Future<void> activate(
    ToolSummary tool, {
    double? lat,
    double? lon,
  }) async {
    if (!tool.isOwned) return;
    final kind = MainParamBuffKind.tryParseToolName(tool.name);
    if (kind == null) return;

    _activating = true;
    _message = null;
    notifyListeners();
    try {
      final session = await _toolService.startToolSession(
        toolId: tool.id,
        lat: lat,
        lon: lon,
      );
      _session = session;
      _tool = tool;
      _kind = MainParamBuffKind.tryParseActionKey(session.actionKey) ?? kind;
      _requestShowOnMap = true;
      _ensureTickTimer();
      _message = '${_kind!.toolName} active';
    } catch (error) {
      _message = error.toString();
    } finally {
      _activating = false;
      notifyListeners();
    }
  }

  Future<void> stop({bool notifyServer = true}) async {
    _tickTimer?.cancel();
    _tickTimer = null;
    final hadSession = _session != null;
    if (notifyServer && hadSession) {
      try {
        await _toolService.cancelSession(_session!.sessionId);
      } catch (_) {
        // Local stop still clears HUD / buffs.
      }
    }
    _session = null;
    _tool = null;
    _kind = null;
    _message = null;
    remainingListenable.value = null;
    if (hadSession) notifyListeners();
  }

  /// Clear local UI when another tool session took over on the server.
  void clearLocalSession() {
    if (_session == null) return;
    unawaited(stop(notifyServer: false));
  }

  /// Stop if the session is period-gated and [weatherTime] left the allow-list.
  Future<void> stopIfPeriodLeft(String? weatherTime) async {
    if (!isActive) return;
    if (isLiveForWeatherTime(weatherTime)) return;
    await stop(notifyServer: true);
  }

  void _ensureTickTimer() {
    _tickTimer?.cancel();
    _syncRemaining();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_syncRemaining()) return;
      if (!isActive) {
        unawaited(stop(notifyServer: false));
      }
    });
  }

  /// Returns true when the session expired and local cleanup was started.
  bool _syncRemaining() {
    return syncTimedSessionRemaining(
      session: _session,
      remainingListenable: remainingListenable,
      onExpired: () => unawaited(stop(notifyServer: false)),
    );
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    remainingListenable.dispose();
    super.dispose();
  }
}

/// Back-compat: prefer [MainParamBuffController] directly.
@Deprecated('Use MainParamBuffController')
typedef RidgeGlassController = MainParamBuffController;

@Deprecated('Use MainParamBuffController')
typedef ExpeditionDrivetrainController = MainParamBuffController;
