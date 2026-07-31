import 'package:flutter/material.dart';

import '../../theme/map_chrome_theme.dart';
import 'drawer_sheet_sizes.dart';
import 'draggable_sheet_wrapper.dart';

/// Shared Catalog bottom drawer shell: title + scrollable body.
class CatalogAlbumDrawer extends StatelessWidget {
  const CatalogAlbumDrawer({
    super.key,
    required this.scrollController,
    required this.body,
    this.title = 'Catalog',
  });

  final ScrollController scrollController;
  final Widget body;
  final String title;

  /// Catalog album opens taller than filter sheets.
  static const double initialChildSize = 0.9;

  static Future<void> show(
    BuildContext context, {
    required Widget Function(ScrollController scrollController) builder,
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
      builder: (_) => DraggableSheetWrapper(
        initialChildSize: initialChildSize,
        minChildSize: DrawerSheetSizes.minChildSize,
        maxChildSize: DrawerSheetSizes.maxChildSize,
        childBuilder: builder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: SizedBox(
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontFamily: MapChromeTheme.serifFont,
                      fontWeight: FontWeight.w600,
                      color: MapChromeTheme.brownText,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(
                        Icons.close,
                        color: MapChromeTheme.brownText.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: MapChromeTheme.parchmentEdge.withValues(alpha: 0.85),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Paginated 3-column catalog grid used inside [CatalogAlbumDrawer].
class CatalogAlbumGrid extends StatelessWidget {
  const CatalogAlbumGrid({
    super.key,
    required this.scrollController,
    required this.itemCount,
    required this.itemBuilder,
    required this.hasMore,
    required this.isLoading,
    required this.onLoadMore,
    this.errorMessage,
    this.onRetry,
    this.emptyMessage = 'No cards in the catalog yet.',
  });

  final ScrollController scrollController;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool hasMore;
  final bool isLoading;
  final VoidCallback onLoadMore;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final String emptyMessage;

  static const int crossAxisCount = 3;
  static const double spacing = 10;

  @override
  Widget build(BuildContext context) {
    if (errorMessage != null && itemCount == 0) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(24),
        children: [
          Text(errorMessage!, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            Center(
              child: FilledButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ),
          ],
        ],
      );
    }

    if (!isLoading && itemCount == 0) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(24),
        children: [
          Text(emptyMessage, textAlign: TextAlign.center),
        ],
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 400 &&
            hasMore &&
            !isLoading) {
          onLoadMore();
        }
        return false;
      },
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                childAspectRatio: 1086 / 1448,
              ),
              delegate: SliverChildBuilderDelegate(
                itemBuilder,
                childCount: itemCount,
              ),
            ),
          ),
          if (isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
