import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/dinosaur.dart';
import '../common/drawer_sheet_sizes.dart';
import 'dinosaur_wikipedia_view.dart';

class DinosaurArticleDrawer extends StatelessWidget {
  const DinosaurArticleDrawer({super.key, required this.dinosaur});

  final DinosaurSummary dinosaur;

  static Future<void> show(
    BuildContext context, {
    required DinosaurSummary dinosaur,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DinosaurArticleDrawer(dinosaur: dinosaur),
    );
  }

  static String? wikipediaAsOfLabel(DateTime? insertDate) {
    if (insertDate == null) return null;
    final local = insertDate.toLocal();
    final formatted = DateFormat.yMMMMd().format(local);
    return 'Wikipedia as of $formatted';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = dinosaur.wikipediaTitle.trim();
    final asOfLabel = wikipediaAsOfLabel(dinosaur.insertDate);

    // Fixed height (not DraggableScrollableSheet) so the WebView owns
    // vertical scroll gestures instead of competing with sheet dragging.
    return SizedBox(
      height: MediaQuery.sizeOf(context).height *
          DrawerSheetSizes.initialChildSize,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title.replaceAll('_', ' '),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (asOfLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    asOfLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(1),
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.outlineVariant.withValues(alpha: 0),
                        colorScheme.outlineVariant.withValues(alpha: 0.7),
                        colorScheme.outlineVariant.withValues(alpha: 0),
                      ],
                    ),
                  ),
                  child: const SizedBox(height: 1),
                ),
              ],
            ),
          ),
          Expanded(
            child: title.isEmpty
                ? const _MessagePane(
                    icon: Icons.article_outlined,
                    message:
                        'No Wikipedia article is linked for this dinosaur yet.',
                  )
                : DinosaurWikipediaView(
                    wikipediaTitle: title,
                    asOf: dinosaur.insertDate,
                    preferDark: theme.brightness == Brightness.dark,
                  ),
          ),
        ],
      ),
    );
  }
}

class _MessagePane extends StatelessWidget {
  const _MessagePane({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
