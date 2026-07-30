import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import 'dinosaur_card_back.dart';
import 'dinosaur_card_front.dart';
import 'dinosaur_status_helper.dart';
import 'turnable_y_axis_card.dart';

class DinosaurTurnableCard extends StatefulWidget {
  const DinosaurTurnableCard({
    super.key,
    required this.dinosaur,
    this.showFrontFacts = true,
    this.showArticleButton,
    this.turnable = true,
    this.enableDragFlip = true,
    this.outerPadding =
        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.fixedFaceHeight,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
    this.overlayHeightFactor = 0.52,
    this.onDinosaurUpdated,
  });

  final DinosaurSummary dinosaur;
  final bool showFrontFacts;
  final bool? showArticleButton;
  final bool turnable;
  final bool enableDragFlip;
  final EdgeInsets outerPadding;
  final double? fixedFaceHeight;
  final double titleFontSize;
  final double subtitleFontSize;
  final double overlayHeightFactor;
  final ValueChanged<DinosaurSummary>? onDinosaurUpdated;

  @override
  State<DinosaurTurnableCard> createState() => _DinosaurTurnableCardState();
}

class _DinosaurTurnableCardState extends State<DinosaurTurnableCard> {
  late DinosaurSummary _dinosaur;

  @override
  void initState() {
    super.initState();
    _dinosaur = widget.dinosaur;
  }

  @override
  void didUpdateWidget(covariant DinosaurTurnableCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dinosaur.id != widget.dinosaur.id ||
        oldWidget.dinosaur.status != widget.dinosaur.status) {
      _dinosaur = widget.dinosaur;
    }
  }

  Future<void> _onStatusSelected(String status) async {
    final updated = await applyDinosaurStatusSelection(
      context,
      _dinosaur,
      newStatus: status,
    );
    if (updated == null || !mounted) return;
    setState(() => _dinosaur = updated);
    widget.onDinosaurUpdated?.call(updated);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin =
        context.watch<AuthController>().currentUser?.isAdmin ?? false;
    final isCatalog = !_dinosaur.isInventoryOccurrence;
    // Catalog: admins always get a tappable badge (incl. Hidden).
    // Non-admins only see a badge when they already have a non-hidden status.
    // Inventory: non-tappable status when present.
    final status = _dinosaur.status?.trim();
    final hasStatus = status != null && status.isNotEmpty;
    final showStatus = isCatalog
        ? (isAdmin || (hasStatus && !_dinosaur.isHidden))
        : (hasStatus && !_dinosaur.isHidden);
    final canEditStatus = isCatalog && isAdmin && showStatus;

    return TurnableYAxisCard(
      resetIdentity: _dinosaur.id,
      borderRadius: DinoCardTheme.borderRadius,
      outerPadding: widget.outerPadding,
      fixedFaceHeight: widget.fixedFaceHeight,
      decoration: DinoCardTheme.of(context).chromeDecoration(),
      turnable: widget.turnable,
      enableDragFlip: widget.enableDragFlip,
      front: DinosaurCardFront(
        dinosaur: _dinosaur,
        showFacts: widget.showFrontFacts,
        titleFontSize: widget.titleFontSize,
        subtitleFontSize: widget.subtitleFontSize,
        overlayHeightFactor: widget.overlayHeightFactor,
        showStatus: showStatus,
        onStatusSelected: canEditStatus ? _onStatusSelected : null,
      ),
      back: DinosaurCardBack(
        dinosaur: _dinosaur,
        showArticleButton: widget.showArticleButton ?? widget.showFrontFacts,
        titleFontSize: widget.titleFontSize,
        subtitleFontSize: widget.subtitleFontSize,
      ),
    );
  }
}
