import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../models/fossil.dart';
import '../../theme/dino_card_theme.dart';
import 'card_discard_helper.dart';
import 'fossil_card_back.dart';
import 'fossil_card_front.dart';
import 'fossil_status_helper.dart';
import 'turnable_y_axis_card.dart';

class FossilTurnableCard extends StatefulWidget {
  const FossilTurnableCard({
    super.key,
    required this.fossil,
    this.turnable = true,
    this.enableDragFlip = true,
    this.enableLongPressActions = false,
    this.autoFlipOnce = false,
    this.autoFlipHoldOnBack = Duration.zero,
    this.outerPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.fixedFaceHeight,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
    this.overlayHeightFactor = 0.38,
    this.onFossilUpdated,
  });

  final FossilSummary fossil;
  final bool turnable;
  final bool enableDragFlip;
  final bool enableLongPressActions;
  final bool autoFlipOnce;
  final Duration autoFlipHoldOnBack;
  final EdgeInsets outerPadding;
  final double? fixedFaceHeight;
  final double titleFontSize;
  final double subtitleFontSize;
  final double overlayHeightFactor;
  final ValueChanged<FossilSummary>? onFossilUpdated;

  @override
  State<FossilTurnableCard> createState() => _FossilTurnableCardState();
}

class _FossilTurnableCardState extends State<FossilTurnableCard> {
  late FossilSummary _fossil;

  @override
  void initState() {
    super.initState();
    _fossil = widget.fossil;
  }

  @override
  void didUpdateWidget(covariant FossilTurnableCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fossil.id != widget.fossil.id ||
        oldWidget.fossil.status != widget.fossil.status) {
      _fossil = widget.fossil;
    }
  }

  Future<void> _onStatusSelected(String status) async {
    final updated = await applyFossilStatusSelection(
      context,
      _fossil,
      newStatus: status,
    );
    if (updated == null || !mounted) return;
    setState(() => _fossil = updated);
    widget.onFossilUpdated?.call(updated);
  }

  @override
  Widget build(BuildContext context) {
    final hasStatus = (_fossil.status?.trim().isNotEmpty ?? false);
    final showAdminUi = context.watch<AuthController>().showAdminUi;
    final canEditStatus = hasStatus && showAdminUi && _fossil.isField;

    return TurnableYAxisCard(
      resetIdentity: _fossil.id,
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
              onThrowAway: () => discardFossilFromInventory(context, _fossil),
            )
          : null,
      autoFlipOnce: widget.autoFlipOnce,
      autoFlipHoldOnBack: widget.autoFlipHoldOnBack,
      front: FossilCardFront(
        fossil: _fossil,
        titleFontSize: widget.titleFontSize,
        subtitleFontSize: widget.subtitleFontSize,
        overlayHeightFactor: widget.overlayHeightFactor,
        onStatusSelected: canEditStatus ? _onStatusSelected : null,
      ),
      back: FossilCardBack(
        fossil: _fossil,
        titleFontSize: widget.titleFontSize,
        subtitleFontSize: widget.subtitleFontSize,
      ),
    );
  }
}
