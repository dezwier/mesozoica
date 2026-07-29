import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/tool_action_router.dart';
import '../../controllers/tool_catalog_controller.dart';
import '../../models/tool.dart';
import '../../services/tool_service.dart';
import '../../theme/dino_card_theme.dart';
import '../tool/tool_params_edit_sheet.dart';
import '../../models/aerial_mission_kind.dart';
import '../../models/formation_map_kind.dart';
import '../../models/guidance_tool_kind.dart';
import 'tool_card_back.dart';
import 'tool_card_extension.dart';
import 'tool_card_front.dart';
import 'turnable_y_axis_card.dart';

class ToolTurnableCard extends StatefulWidget {
  const ToolTurnableCard({
    super.key,
    required this.tool,
    this.turnable = true,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
    this.overlayHeightFactor = 0.52,
  });

  final ToolSummary tool;
  final bool turnable;
  final double titleFontSize;
  final double subtitleFontSize;
  final double overlayHeightFactor;

  @override
  State<ToolTurnableCard> createState() => _ToolTurnableCardState();
}

class _ToolTurnableCardState extends State<ToolTurnableCard> {
  bool _collectBusy = false;
  bool _updateParamsBusy = false;

  List<String> _editableKeysForBackStats(ToolSummary tool) {
    final aerial = AerialMissionKind.tryParseToolName(tool.name);
    if (aerial != null) {
      return const [
        'flight_speed_kmh',
        'max_route_km',
        'discovery_chance',
        'discovery_distance_m',
      ];
    }

    final guidance = GuidanceToolKind.tryParseToolName(tool.name);
    if (guidance != null) {
      return switch (guidance) {
        GuidanceToolKind.geoCompass => const [
            'duration_minutes',
            'exactness',
            'discovery_chance',
          ],
        GuidanceToolKind.proximityScanner => const [
            'duration_minutes',
            'exactness',
          ],
        GuidanceToolKind.siteNavigator => const [
            'duration_minutes',
            'direction_exactness',
            'distance_exactness',
            'discovery_chance',
          ],
      };
    }

    if (FormationMapKind.matchesToolName(tool.name)) {
      return const [
        'duration_minutes',
        'accuracy',
        'range',
      ];
    }

    return tool.params.keys.toList(growable: false);
  }

  Future<void> _onCollect() async {
    if (_collectBusy) return;
    setState(() => _collectBusy = true);
    try {
      await context.read<ToolCatalogController>().collectTool(widget.tool.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Added to your collection')));
    } on ToolServiceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to add tool')));
    } finally {
      if (mounted) {
        setState(() => _collectBusy = false);
      }
    }
  }

  Future<void> _onAction() async {
    ToolActionRouter.start(context, widget.tool);
  }

  Future<void> _onEditParams() async {
    if (_updateParamsBusy) return;
    final inventoryMode =
        context.read<ToolCatalogController>().mode == ToolScreenMode.inventory;
    final paramsForEdit =
        widget.tool.params.isNotEmpty ? widget.tool.params : widget.tool.baseParams;

    final editableKeys = _editableKeysForBackStats(widget.tool)
        .where(paramsForEdit.containsKey)
        .toList(growable: false);

    // Defensive fallback: if the params payload doesn't include a key we
    // expect, keep the modal usable by showing whatever keys we got.
    final safeEditableKeys =
        editableKeys.isNotEmpty ? editableKeys : paramsForEdit.keys.toList(growable: false);

    if (!inventoryMode) return;

    await ToolParamsEditSheet.show(
      context,
      params: paramsForEdit,
      editableKeys: safeEditableKeys,
      onSave: (updatedParams) async {
        if (_updateParamsBusy) return;
        setState(() => _updateParamsBusy = true);
        try {
          final updatedTool = await ToolService().updateToolParams(
            widget.tool.id,
            updatedParams,
          );
          if (!mounted) return;
          context.read<ToolCatalogController>().replaceToolSummary(updatedTool);
        } on ToolServiceException catch (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.message)));
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to update tool parameters')),
          );
        } finally {
          if (mounted) {
            setState(() => _updateParamsBusy = false);
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin =
        context.watch<AuthController>().currentUser?.isAdmin ?? false;
    final inventoryMode =
        context.watch<ToolCatalogController>().mode == ToolScreenMode.inventory;
    final paramsForEdit =
        widget.tool.params.isNotEmpty ? widget.tool.params : widget.tool.baseParams;
    final showCollectBadge = isAdmin && !widget.tool.isOwned;
    final extension = ToolCardExtensions.forTool(widget.tool);
    final onInfo = extension?.infoHandler(context, widget.tool);
    final statsChild = extension?.buildDeployStats(context, widget.tool);
    final ongoingChild = extension?.buildOngoingPanel(context, widget.tool);
    final canEditParams =
        widget.tool.isOwned && inventoryMode && isAdmin && paramsForEdit.isNotEmpty;

    return TurnableYAxisCard(
      resetIdentity: widget.tool.id,
      borderRadius: DinoCardTheme.borderRadius,
      outerPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: DinoCardTheme.of(context).chromeDecoration(),
      turnable: widget.turnable,
      front: ToolCardFront(
        tool: widget.tool,
        titleFontSize: widget.titleFontSize,
        subtitleFontSize: widget.subtitleFontSize,
        overlayHeightFactor: widget.overlayHeightFactor,
        showCollectBadge: showCollectBadge,
        collectBusy: _collectBusy,
        onCollect: showCollectBadge ? _onCollect : null,
      ),
      back: ToolCardBack(
        tool: widget.tool,
        titleFontSize: widget.titleFontSize,
        subtitleFontSize: widget.subtitleFontSize,
        onAction: inventoryMode && widget.tool.isOwned ? _onAction : null,
        onInfo: inventoryMode ? onInfo : null,
        onEditParams: canEditParams ? _onEditParams : null,
        showInstanceId: inventoryMode,
        showActionButtons: inventoryMode,
        statsChild: statsChild,
        ongoingChild: ongoingChild,
      ),
    );
  }
}
