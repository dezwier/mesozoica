import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/aerial_recon_controller.dart';
import '../../controllers/tool_action_router.dart';
import '../../services/tool_service.dart';
import '../common/drawer_sheet_sizes.dart';

/// Bottom sheet listing ongoing and past Aerial Recon missions.
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
    final ongoing = recon.missions.where((m) => m.isActive).toList();
    final past = recon.missions.where((m) => m.isPast).toList();
    final empty = ongoing.isEmpty && past.isEmpty && !recon.missionsLoading;

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
                    'Ongoing and past scout loops',
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
                          'No recons yet — Deploy to scout a loop.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (ongoing.isNotEmpty) ...[
                      _SectionHeader(label: 'Ongoing'),
                      ...ongoing.map(
                        (m) => _MissionTile(
                          mission: m,
                          onTap: () => _select(m),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
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
    final statusLabel = _statusLabel(mission.status);
    final subtitle = _subtitle(mission);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        title: Text(
          '${mission.routeLengthKm.toStringAsFixed(1)} km · $statusLabel',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: Icon(
          mission.isActive ? Icons.my_location : Icons.route,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'ensuring':
        return 'Preparing';
      case 'flying':
        return 'In flight';
      case 'done':
        return 'Completed';
      case 'failed':
        return 'Failed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  static String _subtitle(AerialReconMission mission) {
    final durationMin = (mission.flightDurationS / 60).round();
    final durationLabel = durationMin <= 1
        ? '${mission.flightDurationS}s flight'
        : '$durationMin min flight';
    if (mission.isActive) {
      if (mission.isFlying && mission.flightEndsAt != null) {
        final left = mission.flightEndsAt!.difference(DateTime.now().toUtc());
        if (left.isNegative) return '$durationLabel · finishing…';
        final mins = left.inMinutes;
        if (mins < 1) return '$durationLabel · <1 min left';
        return '$durationLabel · $mins min left';
      }
      return '$durationLabel · preparing terrain';
    }
    final ended = mission.flightEndsAt ?? mission.createdAt;
    return '$durationLabel · ${_relative(ended)}';
  }

  static String _relative(DateTime utc) {
    final local = utc.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${local.month}/${local.day}/${local.year}';
  }
}
