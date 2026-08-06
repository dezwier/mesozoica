import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';
import '../../utils/display_text.dart';

/// Field-fossil status options shown in the badge dropdown.
class FossilStatusOption {
  const FossilStatusOption({required this.apiStatus, required this.label});

  final String apiStatus;
  final String label;
}

const List<FossilStatusOption> kFossilStatusOptions = [
  FossilStatusOption(apiStatus: 'hidden', label: 'Hidden'),
  FossilStatusOption(apiStatus: 'in_situ', label: 'In situ'),
  FossilStatusOption(apiStatus: 'located', label: 'Located'),
  FossilStatusOption(apiStatus: 'excavated', label: 'Excavated'),
  FossilStatusOption(apiStatus: 'transport', label: 'Transport'),
  FossilStatusOption(apiStatus: 'storage', label: 'Storage'),
  FossilStatusOption(apiStatus: 'analysed', label: 'Analysed'),
];

/// Subtle status chip for field fossil cards with optional status menu.
class FossilStatusBadge extends StatelessWidget {
  const FossilStatusBadge({
    super.key,
    required this.status,
    this.onStatusSelected,
  });

  final String status;
  final ValueChanged<String>? onStatusSelected;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final label = capitalizeLeadingLetter(status.trim().replaceAll('_', ' '));
    if (label.isEmpty) return const SizedBox.shrink();

    final chip = DecoratedBox(
      decoration: BoxDecoration(
        color: cardTheme.cardBackground.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: cardTheme.cardTextPrimary.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            color: cardTheme.cardTextPrimary.withValues(alpha: 0.78),
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
            height: 1.1,
          ),
        ),
      ),
    );

    if (onStatusSelected == null) return chip;

    final current = status.trim().toLowerCase();
    return PopupMenuButton<String>(
      tooltip: 'Change fossil status',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 28),
      onSelected: onStatusSelected,
      itemBuilder: (context) => [
        for (final option in kFossilStatusOptions)
          PopupMenuItem<String>(
            value: option.apiStatus,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: current == option.apiStatus
                      ? Icon(
                          Icons.check,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                ),
                const SizedBox(width: 4),
                Text(option.label),
              ],
            ),
          ),
      ],
      child: chip,
    );
  }
}
