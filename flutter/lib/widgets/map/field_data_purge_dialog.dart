import 'package:flutter/material.dart';

/// Confirmation dialog for wiping all procedural field world data.
class FieldDataPurgeDialog extends StatelessWidget {
  const FieldDataPurgeDialog({super.key});

  static Future<bool> confirm(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => const FieldDataPurgeDialog(),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: const Text('Delete field world?'),
      content: const Text(
        'This permanently deletes all field sites and field fossils '
        '(and related jobs) for everyone. Archive data is kept.\n\n'
        'This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            'Delete all',
            style: TextStyle(color: errorColor),
          ),
        ),
      ],
    );
  }
}
