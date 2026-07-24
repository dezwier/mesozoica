import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/aerial_recon_controller.dart';
import '../../services/tool_service.dart';

/// Shared Follow / Abort controls for an active aerial recon mission.
class AerialReconMissionActions extends StatelessWidget {
  const AerialReconMissionActions({
    super.key,
    required this.mission,
    this.showFollow = true,
    this.showAbort = true,
  });

  final AerialReconMission mission;
  final bool showFollow;
  final bool showAbort;

  @override
  Widget build(BuildContext context) {
    if (!showFollow && !showAbort) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    // Muted brown-red — softer than Material error red.
    const abortColor = Color(0xFF8B5A4A);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (showFollow)
          _ReconActionChip(
            label: 'Follow recon',
            icon: Icons.center_focus_strong_rounded,
            onPressed: () =>
                context.read<AerialReconController>().focusMission(mission),
            foreground: onSurface.withValues(alpha: 0.72),
            background: onSurface.withValues(alpha: 0.05),
            border: onSurface.withValues(alpha: 0.14),
          ),
        if (showFollow && showAbort) const SizedBox(width: 8),
        if (showAbort)
          _ReconActionChip(
            label: 'Abort recon',
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
    AerialReconMission mission,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        const abortColor = Color.fromARGB(255, 136, 68, 55);
        return AlertDialog(
          title: const Text('Abort Aerial Recon?'),
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
              style: TextButton.styleFrom(foregroundColor: abortColor),
              child: const Text('Abort recon'),
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
        SnackBar(content: Text(message ?? 'Failed to abort Aerial Recon')),
      );
    }
  }
}

class _ReconActionChip extends StatelessWidget {
  const _ReconActionChip({
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.1,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
