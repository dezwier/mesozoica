import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/disguise_tool_kind.dart';
import '../models/tool.dart';
import '../models/tool_session.dart';
import '../services/tool_service.dart';
import 'timed_session_remaining.dart';

/// Active timed disguise cover, or map pick-mode before deploy.
class DisguiseSessionController extends ChangeNotifier {
  DisguiseSessionController({ToolService? toolService})
      : _toolService = toolService ?? ToolService();

  final ToolService _toolService;

  ToolSession? _session;
  ToolSummary? _tool;
  DisguiseToolKind? _kind;
  bool _activating = false;
  bool _pickMode = false;
  bool _requestShowOnMap = false;
  String? _message;
  Timer? _tickTimer;

  final ValueNotifier<Duration?> remainingListenable =
      ValueNotifier<Duration?>(null);

  bool get isActive =>
      _session != null && _session!.isActive && !_session!.isExpired;
  bool get isPickMode => _pickMode;
  bool get requestShowOnMap => _requestShowOnMap;
  ToolSession? get session => _session;
  ToolSummary? get tool => _tool;
  DisguiseToolKind? get kind => _kind;
  bool get isActivating => _activating;
  String? get message => _message;
  int? get coveredSiteId {
    final raw = _session?.state['site_id'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return null;
  }

  Duration? get remaining => remainingListenable.value;

  void consumeShowOnMapRequest() {
    _requestShowOnMap = false;
  }

  /// Enter map pick mode for [tool]; user taps a site then confirms.
  void beginPick(ToolSummary tool) {
    if (!tool.isOwned) return;
    final kind = DisguiseToolKind.tryParseToolName(tool.name);
    if (kind == null) return;
    _pickMode = true;
    _tool = tool;
    _kind = kind;
    _message = null;
    _requestShowOnMap = true;
    notifyListeners();
  }

  void cancelPick() {
    if (!_pickMode) return;
    _pickMode = false;
    if (!isActive) {
      _tool = null;
      _kind = null;
    }
    _message = null;
    notifyListeners();
  }

  Future<void> restoreActiveSession() async {
    if (_activating) return;
    try {
      for (final kind in DisguiseToolKind.values) {
        final session = await _toolService.fetchActiveSession(
          actionKey: kind.actionKey,
        );
        if (session == null || !session.isActive || session.isExpired) {
          continue;
        }
        if (_session?.sessionId == session.sessionId && isActive) {
          _session = session;
          _kind = kind;
          _ensureTickTimer();
          return;
        }
        _session = session;
        _tool = null;
        _kind = kind;
        _pickMode = false;
        _ensureTickTimer();
        _message = '${kind.toolName} active';
        notifyListeners();
        return;
      }
      if (_session != null && !isActive) {
        await stop(notifyServer: false);
      }
    } catch (error) {
      debugPrint('Disguise restore failed: $error');
    }
  }

  Future<void> activate(ToolSummary tool, {required int siteId}) async {
    if (!tool.isOwned) return;
    final kind = DisguiseToolKind.tryParseToolName(tool.name);
    if (kind == null) return;

    _activating = true;
    _pickMode = false;
    _message = null;
    notifyListeners();
    try {
      final session = await _toolService.startToolSession(
        toolId: tool.id,
        siteId: siteId,
      );
      _session = session;
      _tool = tool;
      _kind = kind;
      _ensureTickTimer();
      _message = '${kind.toolName} covering site $siteId';
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
    final wasPicking = _pickMode;
    if (notifyServer && hadSession) {
      try {
        await _toolService.cancelSession(_session!.sessionId);
      } catch (_) {
        // Local stop still clears HUD / cover.
      }
    }
    _session = null;
    _tool = null;
    _kind = null;
    _pickMode = false;
    _message = null;
    remainingListenable.value = null;
    if (hadSession || wasPicking) notifyListeners();
  }

  void clearLocalSession() {
    if (_session == null && !_pickMode) return;
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
