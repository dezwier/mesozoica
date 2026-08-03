import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/game_config.dart';
import '../../config/tool_params_edit.dart';
import '../../controllers/aerial_session_controller.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/formation_map_controller.dart';
import '../../controllers/guidance_session_controller.dart';
import '../../controllers/orbit_survey_controller.dart';
import '../../controllers/ridge_glass_controller.dart';
import '../../controllers/terrain_echo_controller.dart';
import '../../controllers/tool_action_router.dart';
import '../../controllers/tool_catalog_controller.dart';
import '../../models/aerial_action_kind.dart';
import '../../models/tool.dart';
import '../../models/tool_session.dart';
import '../../services/tool_service.dart';
import '../../theme/dino_card_theme.dart';
import '../common/app_toast.dart';
import '../tools/filters/tool_params_edit_sheet.dart';
import 'card_discard_helper.dart';
import 'tool_card_back.dart';
import 'tool_card_extension.dart';
import 'tool_card_front.dart';
import 'turnable_y_axis_card.dart';

class ToolTurnableCard extends StatefulWidget {
  const ToolTurnableCard({
    super.key,
    required this.tool,
    this.turnable = true,
    this.enableDragFlip = true,
    this.enableLongPressActions = false,
    this.outerPadding =
        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.fixedFaceHeight,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
    this.overlayHeightFactor = 0.52,
  });

  final ToolSummary tool;
  final bool turnable;
  final bool enableDragFlip;
  final bool enableLongPressActions;
  final EdgeInsets outerPadding;
  final double? fixedFaceHeight;
  final double titleFontSize;
  final double subtitleFontSize;
  final double overlayHeightFactor;

  @override
  State<ToolTurnableCard> createState() => _ToolTurnableCardState();
}

class _ToolTurnableCardState extends State<ToolTurnableCard> {
  bool _updateParamsBusy = false;
  bool _historyLoading = false;
  List<ToolHistoryEntry> _history = const [];
  List<ToolSession> _sessions = const [];
  int? _remainingDurationS;
  int? _totalDurationS;
  Timer? _remainingTick;
  int? _loadedForToolId;
  String? _lastSessionFingerprint;
  bool _historyRefreshQueued = false;
  bool _sessionSyncQueued = false;
  int _historyFetchGen = 0;

  /// Params shown/edited: instance → base → game-config YAML defaults.
  Map<String, dynamic> _paramsForEdit(ToolSummary tool) {
    final defaults =
        GameConfig.instance.toolActions.defaultsForToolName(tool.name);
    final fromTool =
        tool.params.isNotEmpty ? tool.params : tool.baseParams;
    return ToolParamsEdit.mergeDefaults(
      Map<String, dynamic>.from(defaults),
      Map<String, dynamic>.from(fromTool),
    );
  }

  List<String> _editableKeysForBackStats(ToolSummary tool) {
    final params = _paramsForEdit(tool);
    final extension = ToolCardExtensions.forTool(tool);
    final toolKeys = extension?.editableParamKeys(tool) ??
        [
          for (final key in params.keys)
            if (key != 'stats_explanation' && key != 'modifies_main_params')
              key,
        ];
    return ToolParamsEdit.editableKeys(toolKeys: toolKeys, params: params);
  }

  Map<String, String> _editableLabelsFor(ToolSummary tool) {
    return ToolParamsEdit.editableLabels(keys: _editableKeysForBackStats(tool));
  }

  Future<void> _onAction() async {
    ToolActionRouter.start(context, widget.tool);
  }

  bool get _canLoadHistory =>
      widget.tool.isOwned && widget.tool.isToolInstance;

  Future<void> _refreshHistory({bool showSpinner = false}) async {
    final tool = widget.tool;
    if (!_canLoadHistory) return;
    final gen = ++_historyFetchGen;
    _loadedForToolId = tool.id;
    if (showSpinner || _history.isEmpty) {
      setState(() {
        _historyLoading = true;
        _remainingDurationS = tool.remainingDurationS;
        _totalDurationS = tool.totalDurationS;
      });
    }
    try {
      final response = await ToolService().fetchToolSessions(tool.id);
      if (!mounted || widget.tool.id != tool.id || gen != _historyFetchGen) {
        return;
      }
      setState(() {
        _sessions = response.items;
        _history = response.history.isNotEmpty
            ? response.history
            : [
                for (final session in response.items)
                  ToolHistoryEntry(
                    kind: 'session',
                    at: session.startedAt,
                    session: session,
                  ),
              ];
        _remainingDurationS =
            response.remainingDurationS ?? tool.remainingDurationS;
        _totalDurationS = response.totalDurationS ?? tool.totalDurationS;
        _historyLoading = false;
      });
      // Prefer the catalog's current row over [widget.tool] so a concurrent
      // params update is not overwritten by this duration-only refresh.
      final catalog = context.read<ToolCatalogController>();
      final index =
          catalog.catalogItems.indexWhere((item) => item.id == tool.id);
      final base = index >= 0 ? catalog.catalogItems[index] : tool;
      catalog.replaceToolSummary(
        base.copyWith(
          remainingDurationS: response.remainingDurationS,
          totalDurationS: response.totalDurationS,
        ),
      );
    } catch (_) {
      if (!mounted || widget.tool.id != tool.id || gen != _historyFetchGen) {
        return;
      }
      setState(() {
        _historyLoading = false;
        if (_history.isEmpty) _loadedForToolId = null;
      });
    }
  }

  void _queueHistoryRefresh({bool showSpinner = false}) {
    if (_historyRefreshQueued) return;
    _historyRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _historyRefreshQueued = false;
      if (!mounted) return;
      unawaited(_refreshHistory(showSpinner: showSpinner));
    });
  }

  /// Stable signature of this tool's live/known sessions across controllers.
  String _sessionFingerprint({
    required AerialSessionController aerial,
    required GuidanceSessionController guidance,
    required OrbitSurveyController orbit,
    required FormationMapController formation,
    required TerrainEchoController terrain,
    required RidgeGlassController ridge,
  }) {
    final toolId = widget.tool.id;
    final parts = <String>[];

    for (final s in aerial.sessions) {
      if (s.toolId != toolId) continue;
      parts.add(
        'a:${s.sessionId}:${s.status}:${s.stopReason}:'
        '${s.discoveredCount}:${s.endedAt?.millisecondsSinceEpoch ?? 0}',
      );
    }

    void addTimed(String tag, ToolSession? session, ToolSummary? tool) {
      if (session == null) return;
      if (session.toolId != toolId && tool?.id != toolId) return;
      parts.add(
        '$tag:${session.sessionId}:${session.status}:${session.stopReason}:'
        '${session.endedAt?.millisecondsSinceEpoch ?? 0}',
      );
    }

    addTimed('g', guidance.session, guidance.tool);
    addTimed('o', orbit.session, orbit.tool);
    addTimed('f', formation.session, formation.tool);
    addTimed('t', terrain.session, terrain.tool);
    addTimed('r', ridge.session, ridge.tool);
    return parts.join('|');
  }

  void _syncHistoryToSessions({
    required AerialSessionController aerial,
    required GuidanceSessionController guidance,
    required OrbitSurveyController orbit,
    required FormationMapController formation,
    required TerrainEchoController terrain,
    required RidgeGlassController ridge,
  }) {
    if (!_canLoadHistory) return;
    final fingerprint = _sessionFingerprint(
      aerial: aerial,
      guidance: guidance,
      orbit: orbit,
      formation: formation,
      terrain: terrain,
      ridge: ridge,
    );
    if (fingerprint == _lastSessionFingerprint) {
      if (_loadedForToolId != widget.tool.id && !_historyLoading) {
        _queueHistoryRefresh(showSpinner: true);
      }
      return;
    }
    final firstLoad = _lastSessionFingerprint == null;
    _lastSessionFingerprint = fingerprint;
    _queueHistoryRefresh(showSpinner: firstLoad && _history.isEmpty);
  }

  Future<void> _onEditParams() async {
    if (_updateParamsBusy) return;
    final paramsForEdit = _paramsForEdit(widget.tool);
    final preferredKeys = _editableKeysForBackStats(widget.tool);
    final editableKeys = preferredKeys.isNotEmpty
        ? preferredKeys
        : paramsForEdit.keys.toList(growable: false);

    await ToolParamsEditSheet.show(
      context,
      params: paramsForEdit,
      editableKeys: editableKeys,
      labels: _editableLabelsFor(widget.tool),
      onSave: (updatedParams) async {
        if (_updateParamsBusy) return;
        setState(() => _updateParamsBusy = true);
        try {
          final payload =
              ToolParamsEdit.syncLegacyDiscoveryChance(updatedParams);
          final updatedTool = await ToolService().updateToolParams(
            widget.tool.id,
            payload,
          );
          if (!mounted) return;
          context.read<ToolCatalogController>().replaceToolSummary(updatedTool);
        } on ToolServiceException catch (error) {
          if (!mounted) return;
          AppToast.error(context, error.message);
        } catch (_) {
          if (!mounted) return;
          AppToast.error(context, 'Failed to update tool parameters');
        } finally {
          if (mounted) {
            setState(() => _updateParamsBusy = false);
          }
        }
      },
    );
  }

  void _onHistoryTap(ToolSession session) {
    if (!AerialActionKind.isAerialActionKey(session.actionKey)) return;
    final aerial = context.read<AerialSessionController>();
    for (final item in aerial.sessions) {
      if (item.sessionId == session.sessionId) {
        aerial.focusSession(item);
        return;
      }
    }
    unawaited(aerial.focusSessionById(session.sessionId));
  }

  /// Lifetime battery left — recomputed from sessions so live rows tick down.
  int? _liveRemainingS({
    required AerialSessionController aerial,
    required GuidanceSessionController guidance,
    required OrbitSurveyController orbit,
    required FormationMapController formation,
    required TerrainEchoController terrain,
    required RidgeGlassController ridge,
  }) {
    final total = _totalDurationS ?? widget.tool.totalDurationS;
    final fallback = _remainingDurationS ?? widget.tool.remainingDurationS;
    if (total == null) return fallback;

    final toolId = widget.tool.id;
    final byId = <int, ToolSession>{
      for (final session in _sessions) session.sessionId: session,
    };
    void upsert(ToolSession? session) {
      if (session == null || session.toolId != toolId) return;
      byId[session.sessionId] = session;
    }

    for (final session in aerial.sessions) {
      upsert(session);
    }
    upsert(guidance.session);
    upsert(orbit.session);
    upsert(formation.session);
    upsert(terrain.session);
    upsert(ridge.session);

    if (byId.isEmpty) return fallback;

    final now = DateTime.now().toUtc();
    var used = 0;
    for (final session in byId.values) {
      used += session.batteryChargeS(now: now);
    }
    final left = total - used;
    return left < 0 ? 0 : left;
  }

  void _syncRemainingTick({required bool inUse}) {
    final needsTick = inUse || _sessions.any((s) => s.isActive);
    if (needsTick) {
      _remainingTick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
      });
    } else if (_remainingTick != null) {
      _remainingTick!.cancel();
      _remainingTick = null;
    }
  }

  bool _matchesTool(ToolSession? session, ToolSummary? tool) {
    if (session == null) return false;
    final toolId = widget.tool.id;
    return session.toolId == toolId || tool?.id == toolId;
  }

  bool _isToolInUse({
    required AerialSessionController aerial,
    required GuidanceSessionController guidance,
    required OrbitSurveyController orbit,
    required FormationMapController formation,
    required TerrainEchoController terrain,
    required RidgeGlassController ridge,
  }) {
    final toolId = widget.tool.id;
    if (aerial.sessions.any((s) => s.toolId == toolId && s.isActive)) {
      return true;
    }
    if (guidance.isActive && _matchesTool(guidance.session, guidance.tool)) {
      return true;
    }
    if (orbit.isActive && _matchesTool(orbit.session, orbit.tool)) {
      return true;
    }
    if (formation.isActive &&
        _matchesTool(formation.session, formation.tool)) {
      return true;
    }
    if (terrain.isActive && _matchesTool(terrain.session, terrain.tool)) {
      return true;
    }
    if (ridge.isActive && _matchesTool(ridge.session, ridge.tool)) {
      return true;
    }
    return _sessions.any((s) => s.isActive);
  }

  @override
  void didUpdateWidget(covariant ToolTurnableCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tool.id != widget.tool.id) {
      _loadedForToolId = null;
      _history = const [];
      _sessions = const [];
      _remainingDurationS = widget.tool.remainingDurationS;
      _totalDurationS = widget.tool.totalDurationS;
      _lastSessionFingerprint = null;
      _historyFetchGen++;
    } else {
      if (oldWidget.tool.remainingDurationS != widget.tool.remainingDurationS &&
          _remainingDurationS == oldWidget.tool.remainingDurationS) {
        _remainingDurationS = widget.tool.remainingDurationS;
      }
      if (oldWidget.tool.totalDurationS != widget.tool.totalDurationS &&
          _totalDurationS == oldWidget.tool.totalDurationS) {
        _totalDurationS = widget.tool.totalDurationS;
      }
    }
  }

  @override
  void dispose() {
    _remainingTick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showAdminUi = context.watch<AuthController>().showAdminUi;
    final inventoryMode =
        context.watch<ToolCatalogController>().mode == ToolScreenMode.inventory;
    final aerial = context.watch<AerialSessionController>();
    final guidance = context.watch<GuidanceSessionController>();
    final orbit = context.watch<OrbitSurveyController>();
    final formation = context.watch<FormationMapController>();
    final terrain = context.watch<TerrainEchoController>();
    final ridge = context.watch<RidgeGlassController>();

    if (inventoryMode && _canLoadHistory && !_sessionSyncQueued) {
      _sessionSyncQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sessionSyncQueued = false;
        if (!mounted) return;
        _syncHistoryToSessions(
          aerial: aerial,
          guidance: guidance,
          orbit: orbit,
          formation: formation,
          terrain: terrain,
          ridge: ridge,
        );
      });
    }

    final extension = ToolCardExtensions.forTool(widget.tool);
    final statsChild = extension?.buildDeployStats(context, widget.tool);
    final canEditParams = showAdminUi && widget.tool.isOwned;
    final inUse = _isToolInUse(
      aerial: aerial,
      guidance: guidance,
      orbit: orbit,
      formation: formation,
      terrain: terrain,
      ridge: ridge,
    );
    _syncRemainingTick(inUse: inUse);
    final remaining = _liveRemainingS(
      aerial: aerial,
      guidance: guidance,
      orbit: orbit,
      formation: formation,
      terrain: terrain,
      ridge: ridge,
    );

    final back = ToolCardBack(
      tool: widget.tool,
      titleFontSize: widget.titleFontSize,
      subtitleFontSize: widget.subtitleFontSize,
      onAction: inventoryMode &&
              widget.tool.isOwned &&
              !inUse &&
              (remaining == null || remaining > 0)
          ? _onAction
          : null,
      onEditParams: canEditParams ? _onEditParams : null,
      showActionButtons: inventoryMode,
      inUse: inUse,
      statsChild: statsChild,
      history: _history,
      historyLoading: _historyLoading,
      remainingDurationS: remaining,
      onHistoryTap: _onHistoryTap,
    );

    return TurnableYAxisCard(
      resetIdentity: widget.tool.id,
      borderRadius: DinoCardTheme.borderRadius,
      outerPadding: widget.outerPadding,
      fixedFaceHeight: widget.fixedFaceHeight,
      decoration: DinoCardTheme.of(context).chromeDecoration(),
      turnable: widget.turnable,
      enableDragFlip: widget.enableDragFlip,
      enableLongPressActions: widget.enableLongPressActions,
      onSettingsPressed: widget.enableLongPressActions
          ? () => openInventoryCardSettings(
                context: context,
                onThrowAway: () =>
                    discardToolFromInventory(context, widget.tool),
              )
          : null,
      front: ToolCardFront(
        tool: widget.tool,
        titleFontSize: widget.titleFontSize,
        subtitleFontSize: widget.subtitleFontSize,
        overlayHeightFactor: widget.overlayHeightFactor,
      ),
      back: back,
    );
  }
}
