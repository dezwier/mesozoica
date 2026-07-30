import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';
import '../../utils/display_text.dart';

/// Dinosaur catalog status options shown in the badge dropdown.
class DinosaurStatusOption {
  const DinosaurStatusOption({
    required this.apiStatus,
    required this.label,
  });

  final String apiStatus;
  final String label;
}

/// Choices when adding a dinosaur from the catalog ("Add" badge).
const List<DinosaurStatusOption> kDinosaurAddStatusOptions = [
  DinosaurStatusOption(apiStatus: 'modelled', label: 'Modelled'),
  DinosaurStatusOption(apiStatus: 'reconstructed', label: 'Reconstructed'),
];

/// Choices when changing an existing collection status.
const List<DinosaurStatusOption> kDinosaurStatusOptions = [
  DinosaurStatusOption(apiStatus: 'hidden', label: 'Hidden'),
  ...kDinosaurAddStatusOptions,
];

/// Subtle status chip for dinosaur cards with optional status menu.
///
/// On catalog cards with no collection link, [status] is `hidden` and the
/// chip label shows **Add** with Modelled / Reconstructed choices.
class DinosaurStatusBadge extends StatelessWidget {
  const DinosaurStatusBadge({
    super.key,
    required this.status,
    this.onStatusSelected,
  });

  final String status;
  final ValueChanged<String>? onStatusSelected;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final current = status.trim().toLowerCase();
    final isAdd = current.isEmpty || current == 'hidden';
    final label = isAdd && onStatusSelected != null
        ? 'Add'
        : capitalizeLeadingLetter(status.trim());
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

    final options =
        isAdd ? kDinosaurAddStatusOptions : kDinosaurStatusOptions;
    return PopupMenuButton<String>(
      tooltip: isAdd ? 'Add to inventory' : 'Change dinosaur status',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 28),
      onSelected: onStatusSelected,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<String>(
            value: option.apiStatus,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: !isAdd && current == option.apiStatus
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
