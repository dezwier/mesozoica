import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/aerial_recon_controller.dart';
import '../../controllers/tool_action_router.dart';
import '../../services/tool_service.dart';
import '../../shell/map_chrome_insets.dart';

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
    if (mission == null) return const SizedBox.shrink();

    final topInset = MapChromeInsets.top(context);
    final theme = Theme.of(context);
    final detail = _detailLine(mission);

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
                    const SizedBox(height: 2),
                    Text(
                      '${_statusLabel(mission.status)} · '
                      '${mission.routeLengthKm.toStringAsFixed(1)} km',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (mission.isActive) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => _confirmCancel(context, mission),
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Cancel recon'),
                        ),
                      ),
                    ],
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

  static Future<void> _confirmCancel(
    BuildContext context,
    AerialReconMission mission,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancel Aerial Recon?'),
          content: const Text(
            'The scout will stop where it is. Sites already found stay '
            'discovered; nothing further will be found on this loop.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep flying'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              child: const Text('Cancel recon'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;

    final ok = await context
        .read<AerialReconController>()
        .cancelMission(mission.missionId);
    if (!context.mounted) return;
    if (!ok) {
      final message = context.read<AerialReconController>().message;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message ?? 'Failed to cancel Aerial Recon')),
      );
    }
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

  static String? _detailLine(AerialReconMission mission) {
    final durationMin = (mission.flightDurationS / 60).round();
    final durationLabel = durationMin <= 1
        ? '${mission.flightDurationS}s flight'
        : '$durationMin min flight';

    if (mission.isFlying && mission.flightEndsAt != null) {
      final left = mission.flightEndsAt!.difference(DateTime.now().toUtc());
      if (left.isNegative) return '$durationLabel · finishing…';
      final mins = left.inMinutes;
      if (mins < 1) return '$durationLabel · <1 min left';
      return '$durationLabel · $mins min left';
    }
    if (mission.isEnsuring) {
      return '$durationLabel · preparing terrain';
    }
    if (mission.status == 'cancelled') {
      final ended = mission.flightEndsAt ?? mission.createdAt;
      final local = ended.toLocal();
      return 'Stopped '
          '${local.month}/${local.day} '
          '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';
    }
    final ended = mission.flightEndsAt ?? mission.createdAt;
    final local = ended.toLocal();
    return '$durationLabel · finished '
        '${local.month}/${local.day} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
