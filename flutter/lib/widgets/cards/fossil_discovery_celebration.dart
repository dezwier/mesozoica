import 'package:flutter/material.dart';

import '../../config/discovery_config.dart';
import '../../models/fossil.dart';
import 'card_detail_sheet.dart';
import 'celebration_title_badge.dart';
import 'fossil_turnable_card.dart';

/// Celebration overlay after a surface fossil is discovered with a site.
Future<void> showFossilDiscoveryCelebration(
  BuildContext context, {
  required FossilSummary fossil,
}) {
  return CardDetailSheet.show<void>(
    context,
    builder: (context) => _FossilDiscoveryCelebrationSheet(fossil: fossil),
  );
}

/// Show celebrations for each surface fossil in sequence.
Future<void> showFossilDiscoveryCelebrations(
  BuildContext context, {
  required List<FossilSummary> fossils,
}) async {
  for (final fossil in fossils) {
    if (!context.mounted) return;
    await showFossilDiscoveryCelebration(context, fossil: fossil);
  }
}

class _FossilDiscoveryCelebrationSheet extends StatefulWidget {
  const _FossilDiscoveryCelebrationSheet({required this.fossil});

  final FossilSummary fossil;

  @override
  State<_FossilDiscoveryCelebrationSheet> createState() =>
      _FossilDiscoveryCelebrationSheetState();
}

class _FossilDiscoveryCelebrationSheetState
    extends State<_FossilDiscoveryCelebrationSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: DiscoveryConfig.celebrationScaleIn,
    );
    _scale = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutBack,
    );
    _scaleController.forward();
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: CardDetailSheetContent(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CelebrationTitleBadge(title: 'Fossil discovered!'),
            const SizedBox(height: 14),
            FossilTurnableCard(
              fossil: widget.fossil,
              autoFlipOnce: true,
              autoFlipHoldOnBack: DiscoveryConfig.autoFlipHoldOnBack,
            ),
          ],
        ),
      ),
    );
  }
}
