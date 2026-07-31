import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../models/dinosaur.dart';
import '../../services/dinosaur_service.dart';
import '../../theme/dino_card_theme.dart';
import 'dinosaur_card_back.dart';
import 'dinosaur_card_front.dart';
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
    this.onDinosaurCollected,
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
  final ValueChanged<DinosaurSummary>? onDinosaurCollected;

  @override
  State<DinosaurTurnableCard> createState() => _DinosaurTurnableCardState();
}

class _DinosaurTurnableCardState extends State<DinosaurTurnableCard> {
  late DinosaurSummary _dinosaur;
  bool _collectBusy = false;

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

  Future<void> _onCollect() async {
    if (_collectBusy) return;
    setState(() => _collectBusy = true);
    final service = DinosaurService();
    try {
      final status = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return SimpleDialog(
            title: const Text('Choose status'),
            children: [
              for (final option in const [
                ('modelled', 'Modelled'),
                ('reconstructed', 'Reconstructed'),
              ])
                SimpleDialogOption(
                  onPressed: () => Navigator.of(dialogContext).pop(option.$1),
                  child: Text(option.$2),
                ),
            ],
          );
        },
      );
      if (!mounted || status == null) return;

      final versions = await service.listDinosaurImageVersions();
      if (!mounted) return;
      if (versions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No image versions available')),
        );
        return;
      }
      final selectedVersion = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return SimpleDialog(
            title: const Text('Choose image version'),
            children: [
              for (final name in versions)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(dialogContext).pop(name),
                  child: Text(name),
                ),
            ],
          );
        },
      );
      if (!mounted || selectedVersion == null) return;

      final typeId = _dinosaur.dinosaurTypeId ?? _dinosaur.id;
      final created = await service.collectDinosaur(
        dinosaurTypeId: typeId,
        status: status,
        version: selectedVersion,
      );
      if (!mounted) return;
      widget.onDinosaurCollected?.call(created);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to your collection')),
      );
    } on DinosaurServiceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to add dinosaur')),
      );
    } finally {
      service.dispose();
      if (mounted) {
        setState(() => _collectBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showAdminUi = context.watch<AuthController>().showAdminUi;
    final isCatalog = !_dinosaur.isInventoryOccurrence;
    final showCollectBadge = showAdminUi && isCatalog;
    final status = _dinosaur.status?.trim();
    final showInventoryStatus = !isCatalog &&
        status != null &&
        status.isNotEmpty &&
        !_dinosaur.isHidden;

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
        showCollectBadge: showCollectBadge,
        collectBusy: _collectBusy,
        onCollect: showCollectBadge ? _onCollect : null,
        showStatus: showInventoryStatus,
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
