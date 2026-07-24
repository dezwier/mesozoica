import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/aerial_recon_controller.dart';
import '../../controllers/tool_action_router.dart';
import '../../services/tool_service.dart';
import '../common/drawer_sheet_sizes.dart';
import 'aerial_recon_flight_stats.dart';

/// Bottom sheet listing past Aerial Recon missions (ongoing lives on tool card).
class AerialReconMissionsSheet extends StatefulWidget {
  const AerialReconMissionsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const AerialReconMissionsSheet(),
    );
  }

  @override
  State<AerialReconMissionsSheet> createState() =>
      _AerialReconMissionsSheetState();
}

class _AerialReconMissionsSheetState extends State<AerialReconMissionsSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AerialReconController>().refreshMissions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recon = context.watch<AerialReconController>();
    final past = recon.missions.where((m) => m.isPast).toList();
    final empty = past.isEmpty && !recon.missionsLoading;

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
                    ToolActionRouter.aerialReconName,
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
            if (recon.missionsLoading && recon.missions.isEmpty)
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
                          'No past recons yet — Deploy to scout a loop.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (past.isNotEmpty) ...[
                      _SectionHeader(label: 'Past'),
                      ...past.map(
                        (m) => _MissionTile(
                          mission: m,
                          onTap: () => _select(m),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  void _select(AerialReconMission mission) {
    context.read<AerialReconController>().focusMission(mission);
    Navigator.of(context).pop();
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _MissionTile extends StatelessWidget {
  const _MissionTile({
    required this.mission,
    required this.onTap,
  });

  final AerialReconMission mission;
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
                    AerialReconMissionSummaryLine(
                      mission: mission,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AerialReconFlightStats.fromMission(mission),
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
