import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/game_config.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/tool_action_router.dart';
import '../../controllers/tool_catalog_controller.dart';
import '../../models/tool.dart';
import '../../services/tool_service.dart';
import '../../theme/dino_card_theme.dart';
import '../tools/filters/tool_params_edit_sheet.dart';
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

  /// Params shown/edited: instance → base → game-config YAML defaults.
  Map<String, dynamic> _paramsForEdit(ToolSummary tool) {
    final defaults =
        GameConfig.instance.toolActions.defaultsForToolName(tool.name);
    final fromTool =
        tool.params.isNotEmpty ? tool.params : tool.baseParams;
    if (fromTool.isEmpty) return Map<String, dynamic>.from(defaults);
    if (defaults.isEmpty) return Map<String, dynamic>.from(fromTool);
    return {...defaults, ...fromTool};
  }

  List<String> _editableKeysForBackStats(ToolSummary tool) {
    final extension = ToolCardExtensions.forTool(tool);
    if (extension != null) {
      return extension.editableParamKeys(tool);
    }
    return _paramsForEdit(tool).keys.toList(growable: false);
  }

  Future<void> _onAction() async {
    ToolActionRouter.start(context, widget.tool);
  }

  Future<void> _onEditParams() async {
    if (_updateParamsBusy) return;
    final paramsForEdit = _paramsForEdit(widget.tool);
    final preferredKeys = _editableKeysForBackStats(widget.tool);
    // Prefer extension keys (order), but keep any that exist in the payload.
    final editableKeys = preferredKeys.isNotEmpty
        ? preferredKeys
        : paramsForEdit.keys.toList(growable: false);

    await ToolParamsEditSheet.show(
      context,
      params: paramsForEdit,
      editableKeys: editableKeys,
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
    final showAdminUi = context.watch<AuthController>().showAdminUi;
    final inventoryMode =
        context.watch<ToolCatalogController>().mode == ToolScreenMode.inventory;
    final extension = ToolCardExtensions.forTool(widget.tool);
    final onInfo = extension?.infoHandler(context, widget.tool);
    final statsChild = extension?.buildDeployStats(context, widget.tool);
    final ongoingChild = extension?.buildOngoingPanel(context, widget.tool);
    // Admin toggle on: always show the params cog on owned tool cards.
    final canEditParams = showAdminUi && widget.tool.isOwned;

    return TurnableYAxisCard(
      resetIdentity: widget.tool.id,
      borderRadius: DinoCardTheme.borderRadius,
      outerPadding: widget.outerPadding,
      fixedFaceHeight: widget.fixedFaceHeight,
      decoration: DinoCardTheme.of(context).chromeDecoration(),
      turnable: widget.turnable,
      enableDragFlip: widget.enableDragFlip,
      front: ToolCardFront(
        tool: widget.tool,
        titleFontSize: widget.titleFontSize,
        subtitleFontSize: widget.subtitleFontSize,
        overlayHeightFactor: widget.overlayHeightFactor,
      ),
      back: ToolCardBack(
        tool: widget.tool,
        titleFontSize: widget.titleFontSize,
        subtitleFontSize: widget.subtitleFontSize,
        onAction: inventoryMode && widget.tool.isOwned ? _onAction : null,
        onInfo: inventoryMode ? onInfo : null,
        onEditParams: canEditParams ? _onEditParams : null,
        showActionButtons: inventoryMode,
        statsChild: statsChild,
        ongoingChild: ongoingChild,
      ),
    );
  }
}
