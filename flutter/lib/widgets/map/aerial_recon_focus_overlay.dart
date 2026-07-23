import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/aerial_recon_controller.dart';
import '../../controllers/tool_action_router.dart';
import '../../services/tool_service.dart';
import '../../shell/map_chrome_insets.dart';

/// Top banner while a recon mission is focused from the Info sheet.
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
    final ended = mission.flightEndsAt ?? mission.createdAt;
    final local = ended.toLocal();
    return '$durationLabel · finished '
        '${local.month}/${local.day} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
