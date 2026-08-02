import 'package:flutter/material.dart';

import '../common/draggable_sheet_wrapper.dart';

/// Compact settings drawer for inventory cards (throw away / cancel).
Future<void> showCardSettingsDrawer(
  BuildContext context, {
  required Future<void> Function() onThrowAway,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return DraggableSheetWrapper(
        initialChildSize: 0.38,
        minChildSize: 0.25,
        maxChildSize: 0.55,
        childBuilder: (scrollController) {
          return Material(
            color: Theme.of(sheetContext).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(sheetContext)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                  title: Text(
                    'Throw card away',
                    style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.error,
                    ),
                  ),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: sheetContext,
                      builder: (dialogContext) {
                        return AlertDialog(
                          title: const Text('Throw card away?'),
                          content: const Text(
                            'This removes the card from your inventory.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    Theme.of(dialogContext).colorScheme.error,
                              ),
                              child: const Text('Throw away'),
                            ),
                          ],
                        );
                      },
                    );
                    if (confirmed != true) return;
                    if (!sheetContext.mounted) return;
                    Navigator.of(sheetContext).pop();
                    await onThrowAway();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('Cancel'),
                  onTap: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
