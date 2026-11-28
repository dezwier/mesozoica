import 'package:flutter/material.dart';

import '../../utils/display_text.dart';
import 'museum_card_frame.dart';

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
    final label = capitalizeLeadingLetter(status.trim().replaceAll('_', ' '));
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
