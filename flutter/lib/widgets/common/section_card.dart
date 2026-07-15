import 'package:flutter/material.dart';

/// Paginated section card for community lists (Archipelago layout).
class SectionCard<T> extends StatefulWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.items,
    required this.itemBuilder,
    this.isLoading = false,
    this.showVerticalTitle = true,
    this.titleIcon,
    this.initialVisibleCount,
    this.total,
    this.onLoadMore,
    this.isLoadingMore = false,
    this.bottomMargin,
  });

  final String title;
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final bool isLoading;
  final bool showVerticalTitle;
  final IconData? titleIcon;
  final int? initialVisibleCount;
  final int? total;
  final Future<void> Function()? onLoadMore;
  final bool isLoadingMore;
  final double? bottomMargin;

  @override
  State<SectionCard<T>> createState() => _SectionCardState<T>();
}

class _SectionCardState<T> extends State<SectionCard<T>> {
  bool _showAll = false;

  bool get _useServerShowMore =>
      widget.initialVisibleCount != null &&
      widget.total != null &&
      widget.onLoadMore != null;

  @override
  Widget build(BuildContext context) {
    final cardBottomMargin = widget.bottomMargin ?? 12.0;

    if (widget.isLoading) {
      return Card(
        margin: EdgeInsets.only(bottom: cardBottomMargin),
        child: const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final initialCount = widget.initialVisibleCount ?? 0;
    final total = widget.total ?? 0;
    final hasMore = _useServerShowMore &&
        total > 0 &&
        widget.items.length < total &&
        !widget.isLoadingMore;
    final showExpandCollapse = !_useServerShowMore &&
        widget.initialVisibleCount != null &&
        widget.items.length > initialCount;
    final showMoreButton = hasMore || showExpandCollapse;
    final displayItems = _useServerShowMore
        ? widget.items
        : (showExpandCollapse && !_showAll
            ? widget.items.take(initialCount).toList()
            : widget.items);

    return Card(
      margin: EdgeInsets.only(bottom: cardBottomMargin),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showVerticalTitle)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 16, bottom: 12),
              child: SizedBox(
                width: 20,
                child: _buildVerticalTitle(context, widget.title),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...displayItems.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  return Column(
                    children: [
                      if (index > 0)
                        const Divider(
                          height: 1,
                          thickness: 1,
                          indent: 16,
                          endIndent: 16,
                        ),
                      widget.itemBuilder(context, item, index),
                    ],
                  );
                }),
                if (displayItems.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  if (showMoreButton)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                      child: Center(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: hasMore
                                ? () => widget.onLoadMore!()
                                : () => setState(() => _showAll = !_showAll),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: hasMore && widget.isLoadingMore
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.7),
                                      ),
                                    )
                                  : Text(
                                      hasMore
                                          ? 'Show more'
                                          : (_showAll ? 'Show less' : 'Show more'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.7),
                                          ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalTitle(BuildContext context, String title) {
    final textWidget = RotatedBox(
      quarterTurns: -1,
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
      ),
    );
    final iconColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    if (widget.titleIcon != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          textWidget,
          const SizedBox(height: 6),
          RotatedBox(
            quarterTurns: -1,
            child: Icon(widget.titleIcon!, size: 14, color: iconColor),
          ),
        ],
      );
    }
    return textWidget;
  }
}
