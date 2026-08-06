import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';
import '../../utils/display_text.dart';

/// Field-site status options shown in the badge dropdown.
class SiteStatusOption {
  const SiteStatusOption({required this.apiStatus, required this.label});

  final String apiStatus;
  final String label;
}

const List<SiteStatusOption> kSiteStatusOptions = [
  SiteStatusOption(apiStatus: 'hidden', label: 'Hidden'),
  SiteStatusOption(apiStatus: 'discovered', label: 'Discover'),
  SiteStatusOption(apiStatus: 'documented', label: 'Document'),
  SiteStatusOption(apiStatus: 'protected', label: 'Protect'),
  SiteStatusOption(apiStatus: 'excavation', label: 'Excavate'),
  SiteStatusOption(apiStatus: 'exhausted', label: 'Exhaust'),
];

/// Subtle status chip for field site cards with optional status menu.
class SiteStatusBadge extends StatelessWidget {
  const SiteStatusBadge({
    super.key,
    required this.status,
    this.onStatusSelected,
  });

  final String status;
  final ValueChanged<String>? onStatusSelected;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final label = capitalizeLeadingLetter(status.trim());
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
      tooltip: 'Change site status',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 28),
      onSelected: onStatusSelected,
      itemBuilder: (context) => [
        for (final option in kSiteStatusOptions)
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
