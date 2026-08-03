import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/expedition_drivetrain_kind.dart';
import '../models/tool.dart';
import '../models/tool_session.dart';
import '../services/tool_service.dart';
import 'timed_session_remaining.dart';

/// Active timed Expedition Drivetrain session (max discovery speed buff).
class ExpeditionDrivetrainController extends ChangeNotifier {
  ExpeditionDrivetrainController({ToolService? toolService})
      : _toolService = toolService ?? ToolService();

  final ToolService _toolService;

  ToolSession? _session;
  ToolSummary? _tool;
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
  bool get isActivating => _activating;
  String? get message => _message;
  bool get requestShowOnMap => _requestShowOnMap;

  Duration? get remaining => remainingListenable.value;

  Future<void> restoreActiveSession() async {
    if (_activating) return;
    try {
      final session = await _toolService.fetchActiveSession(
        actionKey: ExpeditionDrivetrainKind.actionKey,
      );
      if (session == null || !session.isActive || session.isExpired) {
        if (_session != null && !isActive) {
          await stop(notifyServer: false);
        }
        return;
      }
      if (_session?.sessionId == session.sessionId && isActive) {
        _session = session;
        _ensureTickTimer();
        return;
      }
      _session = session;
      _tool = null;
      _ensureTickTimer();
      _message = '${ExpeditionDrivetrainKind.toolName} active';
      notifyListeners();
    } catch (error) {
      debugPrint('Expedition drivetrain restore failed: $error');
    }
  }

  void consumeShowOnMapRequest() {
    _requestShowOnMap = false;
  }

  Future<void> activate(ToolSummary tool) async {
    if (!tool.isOwned) return;
    if (!ExpeditionDrivetrainKind.matchesToolName(tool.name)) return;

    _activating = true;
    _message = null;
    notifyListeners();
    try {
      final session = await _toolService.startToolSession(toolId: tool.id);
      _session = session;
      _tool = tool;
      _requestShowOnMap = true;
      _ensureTickTimer();
      _message = '${ExpeditionDrivetrainKind.toolName} active';
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
    _message = null;
    remainingListenable.value = null;
    if (hadSession) notifyListeners();
  }

  /// Clear local UI when another tool session took over on the server.
  void clearLocalSession() {
    if (_session == null) return;
    unawaited(stop(notifyServer: false));
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
