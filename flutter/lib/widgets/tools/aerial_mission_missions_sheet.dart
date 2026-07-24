import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/aerial_mission_controller.dart';
import '../../models/aerial_mission_kind.dart';
import '../../services/tool_service.dart';
import '../common/drawer_sheet_sizes.dart';
import 'aerial_mission_flight_stats.dart';

/// Bottom sheet listing past aerial missions (ongoing lives on tool card).
class AerialMissionsSheet extends StatefulWidget {
  const AerialMissionsSheet({super.key, this.kind});

  final AerialMissionKind? kind;

  static Future<void> show(
    BuildContext context, {
    AerialMissionKind? kind,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AerialMissionsSheet(kind: kind),
    );
  }

  @override
  State<AerialMissionsSheet> createState() => _AerialMissionsSheetState();
}

class _AerialMissionsSheetState extends State<AerialMissionsSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AerialMissionController>().refreshMissions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aerial = context.watch<AerialMissionController>();
    final kind = widget.kind;
    final past = aerial.missions.where((m) {
      if (!m.isPast) return false;
      if (kind == null) return true;
      return m.actionKey == kind.actionKey;
    }).toList();
    final empty = past.isEmpty && !aerial.missionsLoading;
    final title = kind?.toolName ?? 'Aerial missions';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: DrawerSheetSizes.initialChildSize,
      minChildSize: DrawerSheetSizes.minChildSize,
      maxChildSize: DrawerSheetSizes.maxChildSize,
      builder: (context, scrollController) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Past scout loops',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (aerial.missionsLoading && aerial.missions.isEmpty)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    if (empty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'No past missions yet — ${kind?.deployVerb ?? 'Deploy'} to scout a loop.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ...past.map(
                      (m) => _MissionTile(
                        mission: m,
                        onTap: () => _select(m),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  void _select(AerialMission mission) {
    context.read<AerialMissionController>().focusMission(mission);
    Navigator.of(context).pop();
  }
}

class _MissionTile extends StatelessWidget {
  const _MissionTile({
    required this.mission,
    required this.onTap,
  });

  final AerialMission mission;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AerialMissionSummaryLine(mission: mission),
                    const SizedBox(height: 10),
                    AerialMissionFlightStats.fromMission(mission),
                  ],
                ),
              ),
              Icon(
                Icons.route,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
