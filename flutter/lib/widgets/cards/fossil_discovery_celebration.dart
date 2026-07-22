import 'package:flutter/material.dart';

import '../../config/discovery_config.dart';
import '../../models/fossil.dart';
import '../../theme/dino_card_theme.dart';
import 'card_detail_sheet.dart';
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
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                'Fossil discovered!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: DinoCardTheme.titleFontFamily,
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  letterSpacing: 0.2,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Color(0xCC000000),
                      blurRadius: 14,
                      offset: Offset(0, 2),
                    ),
                    Shadow(
                      color: Color(0x99000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
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
