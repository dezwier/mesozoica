import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/discovery_config.dart';
import '../../controllers/xp_award_controller.dart';
import '../../models/fossil.dart';
import '../../utils/xp_source_labels.dart';
import 'card_detail_sheet.dart';
import 'celebration_title_badge.dart';
import 'fossil_turnable_card.dart';

/// Celebration overlay after a surface fossil is discovered with a site.
///
/// Fossil XP is claimed once for the sequence and embedded in the first
/// plaque (not shown as a floating badge).
Future<void> showFossilDiscoveryCelebration(
  BuildContext context, {
  required FossilSummary fossil,
  List<XpAward> xpAwards = const [],
}) {
  return CardDetailSheet.show<void>(
    context,
    builder: (context) => _FossilDiscoveryCelebrationSheet(
      fossil: fossil,
      xpAwards: xpAwards,
    ),
  );
}

/// Show celebrations for each surface fossil in sequence.
///
/// Fossil XP (if any) is claimed once and attached to the first celebration.
Future<void> showFossilDiscoveryCelebrations(
  BuildContext context, {
  required List<FossilSummary> fossils,
  List<XpAward>? xpAwards,
}) async {
  if (fossils.isEmpty) return;
  List<XpAward> awards;
  if (xpAwards != null) {
    awards = xpAwards;
  } else {
    try {
      awards = context.read<XpAwardController>().claimCelebrationAwards(
            kFossilDiscoveryCelebrationXpKeys,
          );
    } on ProviderNotFoundException {
      awards = const [];
    }
  }
  for (var i = 0; i < fossils.length; i++) {
    if (!context.mounted) return;
    await showFossilDiscoveryCelebration(
      context,
      fossil: fossils[i],
      xpAwards: i == 0 ? awards : const [],
    );
  }
}

class _FossilDiscoveryCelebrationSheet extends StatefulWidget {
  const _FossilDiscoveryCelebrationSheet({
    required this.fossil,
    this.xpAwards = const [],
  });

  final FossilSummary fossil;
  final List<XpAward> xpAwards;

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
            CelebrationTitleBadge(
              title: 'Fossil discovered!',
              xpAwards: widget.xpAwards,
            ),
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
