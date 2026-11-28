import 'package:flutter/material.dart';

import '../../utils/display_text.dart';
import 'museum_card_frame.dart';

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
    final label = capitalizeLeadingLetter(status.trim());
    if (label.isEmpty) return const SizedBox.shrink();

    final chip = MuseumSectionTab(
      label: label,
      edge: MuseumSectionTabEdge.right,
      fontSize: 9,
      soft: true,
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
