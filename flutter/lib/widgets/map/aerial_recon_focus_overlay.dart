import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/aerial_recon_controller.dart';
import '../../controllers/tool_action_router.dart';
import '../../shell/map_chrome_insets.dart';
import '../tools/aerial_recon_flight_stats.dart';
import '../tools/aerial_recon_mission_actions.dart';

/// Top banner while a recon mission is focused from the Info sheet or scout tap.
class AerialReconFocusOverlay extends StatelessWidget {
  const AerialReconFocusOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final recon = context.watch<AerialReconController>();
    final mission = recon.focusedMission;
    // Rebuild when flying so remaining time updates.
    // ignore: unused_local_variable
    final tick = recon.progressTick;
    // Rebuild when poll updates discovered sites.
    // ignore: unused_local_variable
    final gen = recon.missionsFetchGeneration;
    if (mission == null) return const SizedBox.shrink();

    final topInset = MapChromeInsets.top(context);
    final theme = Theme.of(context);

    return Positioned(
      top: topInset + 8,
      left: 16,
      right: 16,
      child: Material(
        elevation: 2,
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ToolActionRouter.aerialReconName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AerialReconMissionSummaryLine(mission: mission),
                    const SizedBox(height: 8),
                    AerialReconFlightStats.fromMission(mission),
                    const SizedBox(height: 10),
                    AerialReconMissionActions(
                      mission: mission,
                      showAbort: mission.isActive,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    context.read<AerialReconController>().clearFocus(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
