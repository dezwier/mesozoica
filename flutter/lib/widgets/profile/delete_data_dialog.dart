import 'package:flutter/material.dart';

import '../../models/profile.dart';

/// Result of a confirmed selective wipe selection.
class DeleteDataSelection {
  const DeleteDataSelection({
    required this.sites,
    required this.fossils,
    required this.dinosaurs,
  });

  final bool sites;
  final bool fossils;
  final bool dinosaurs;

  bool get hasAny => sites || fossils || dinosaurs;
}

/// Confirmation dialog with checkboxes for progress categories to wipe.
class DeleteDataDialog extends StatefulWidget {
  const DeleteDataDialog({super.key, required this.profile});

  final Profile profile;

  @override
  State<DeleteDataDialog> createState() => _DeleteDataDialogState();
}

class _DeleteDataDialogState extends State<DeleteDataDialog> {
  bool _sites = true;
  bool _fossils = true;
  bool _dinosaurs = true;

  bool get _canConfirm => _sites || _fossils || _dinosaurs;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    final sitesCount = widget.profile.actualSitesCount;
    final fossilsCount = widget.profile.actualFossilsCount;
    final dinosaursCount = widget.profile.actualDinosaursCount;

    return AlertDialog(
      title: const Text('Delete data?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose what to remove. Your account stays active.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _sites,
              onChanged: (value) => setState(() => _sites = value ?? false),
              title: Text('Site progress ($sitesCount)'),
              subtitle: const Text('All sites linked to your account'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _fossils,
              onChanged: (value) => setState(() => _fossils = value ?? false),
              title: Text('Fossil progress ($fossilsCount)'),
              subtitle: const Text('All fossils linked to your account'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _dinosaurs,
              onChanged: (value) =>
                  setState(() => _dinosaurs = value ?? false),
              title: Text('Dino progress ($dinosaursCount)'),
              subtitle: const Text('All dinosaurs linked to your account'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _canConfirm
              ? () => Navigator.pop(
                    context,
                    DeleteDataSelection(
                      sites: _sites,
                      fossils: _fossils,
                      dinosaurs: _dinosaurs,
                    ),
                  )
              : null,
          child: Text(
            'Delete data',
            style: TextStyle(
              color: _canConfirm ? errorColor : errorColor.withValues(alpha: 0.4),
            ),
          ),
        ),
      ],
    );
  }
}
