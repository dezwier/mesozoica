import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/aerial_mission_controller.dart';
import '../../models/aerial_mission_kind.dart';
import '../../shell/map_chrome_insets.dart';
import '../tools/aerial_mission_flight_stats.dart';
import '../tools/aerial_mission_actions.dart';

/// Top banner while an aerial mission is focused from the Info sheet or puck tap.
class AerialMissionFocusOverlay extends StatelessWidget {
  const AerialMissionFocusOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final aerial = context.watch<AerialMissionController>();
    final mission = aerial.focusedMission;
    if (mission == null) return const SizedBox.shrink();

    final topInset = MapChromeInsets.top(context);
    final theme = Theme.of(context);
    final kind = AerialMissionKind.fromActionKey(mission.actionKey);

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
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    aerial.progressTickListenable,
                  ]),
                  builder: (context, _) {
                    // progressTick / fetch generation read for remaining time.
                    // ignore: unused_local_variable
                    final tick = aerial.progressTick;
                    // ignore: unused_local_variable
                    final gen = aerial.missionsFetchGeneration;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          kind.toolName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        AerialMissionSummaryLine(mission: mission),
                        const SizedBox(height: 8),
                        AerialMissionFlightStats.fromMission(mission),
                        if (mission.isActive) ...[
                          const SizedBox(height: 10),
                          AerialMissionActions(mission: mission),
                        ],
                      ],
                    );
                  },
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    context.read<AerialMissionController>().clearFocus(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
