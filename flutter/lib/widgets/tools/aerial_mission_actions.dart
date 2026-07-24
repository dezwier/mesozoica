import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/aerial_mission_controller.dart';
import '../../models/aerial_mission_kind.dart';
import '../../services/tool_service.dart';

/// Shared Follow / Abort controls for an active aerial mission.
class AerialMissionActions extends StatelessWidget {
  const AerialMissionActions({
    super.key,
    required this.mission,
    this.showFollow = true,
    this.showAbort = true,
  });

  final AerialMission mission;
  final bool showFollow;
  final bool showAbort;

  @override
  Widget build(BuildContext context) {
    // Past missions never show Follow / Abort (overlay, card, sheet).
    final follow = showFollow && mission.isActive;
    final abort = showAbort && mission.isActive;
    if (!follow && !abort) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    // Muted brown-red — softer than Material error red.
    const abortColor = Color(0xFF8B5A4A);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (follow)
          _AerialActionChip(
            label: 'Follow',
            icon: Icons.center_focus_strong_rounded,
            onPressed: () =>
                context.read<AerialMissionController>().focusMission(mission),
            foreground: onSurface.withValues(alpha: 0.72),
            background: onSurface.withValues(alpha: 0.05),
            border: onSurface.withValues(alpha: 0.14),
          ),
        if (follow && abort) const SizedBox(width: 8),
        if (abort)
          _AerialActionChip(
            label: 'Abort',
            icon: Icons.cancel_outlined,
            onPressed: () => confirmAbort(context, mission),
            foreground: abortColor,
            background: abortColor.withValues(alpha: 0.08),
            border: abortColor.withValues(alpha: 0.28),
          ),
      ],
    );
  }

  static Future<void> confirmAbort(
    BuildContext context,
    AerialMission mission,
  ) async {
    final kind = AerialMissionKind.fromActionKey(mission.actionKey);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        const abortColor = Color.fromARGB(255, 136, 68, 55);
        return AlertDialog(
          title: Text('${kind.abortLabel}?'),
          content: const Text(
            'The craft will stop where it is. Sites already found stay '
            'discovered; nothing further will be found on this loop.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep flying'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: abortColor),
              child: const Text('Abort'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;

    final ok = await context
        .read<AerialMissionController>()
        .cancelMission(mission.missionId);
    if (!context.mounted) return;
    if (!ok) {
      final message = context.read<AerialMissionController>().message;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message ?? 'Failed to abort ${kind.toolName}'),
        ),
      );
    }
  }
}

class _AerialActionChip extends StatelessWidget {
  const _AerialActionChip({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.foreground,
    required this.background,
    required this.border,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color foreground;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(6);

    return Material(
      color: background,
      borderRadius: radius,
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
