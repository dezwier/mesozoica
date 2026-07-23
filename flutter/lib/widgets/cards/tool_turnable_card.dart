import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/tool_catalog_controller.dart';
import '../../models/tool.dart';
import '../../services/tool_service.dart';
import '../../theme/dino_card_theme.dart';
import 'tool_card_back.dart';
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

  Future<void> _onCollect() async {
    if (_collectBusy) return;
    setState(() => _collectBusy = true);
    try {
      await context.read<ToolCatalogController>().collectTool(widget.tool.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to your collection')),
      );
    } on ToolServiceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to add tool')),
      );
    } finally {
      if (mounted) {
        setState(() => _collectBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin =
        context.watch<AuthController>().currentUser?.isAdmin ?? false;
    final showCollectBadge = isAdmin && !widget.tool.isOwned;

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
      ),
    );
  }
}
