import 'package:flutter/material.dart';

import '../../controllers/fossil_catalog_controller.dart';
import '../cards/geologic_timeline.dart';
import '../common/drawer_sheet_sizes.dart';

class FossilFilterSheet extends StatefulWidget {
  const FossilFilterSheet({
    super.key,
    required this.initialFilters,
    required this.onApply,
    this.catalogTotal,
  });

  final FossilCatalogFilters initialFilters;
  final ValueChanged<FossilCatalogFilters> onApply;
  final int? catalogTotal;

  static Future<void> show(
    BuildContext context, {
    required FossilCatalogFilters initialFilters,
    required ValueChanged<FossilCatalogFilters> onApply,
    int? catalogTotal,
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
      builder: (_) => FossilFilterSheet(
        initialFilters: initialFilters,
        onApply: onApply,
        catalogTotal: catalogTotal,
      ),
    );
  }

  @override
  State<FossilFilterSheet> createState() => _FossilFilterSheetState();
}

class _FossilFilterSheetState extends State<FossilFilterSheet> {
  late final TextEditingController _searchController;
  late String _pendingSearch;
  late RangeValues _pendingRange;
  late bool _pendingOnlyCustomImage;
  bool _applied = false;

  @override
  void initState() {
    super.initState();
    _pendingSearch = widget.initialFilters.searchQuery;
    _searchController = TextEditingController(text: _pendingSearch);
    _pendingRange = RangeValues(
      widget.initialFilters.maYounger,
      widget.initialFilters.maOlder,
    );
    _pendingOnlyCustomImage = widget.initialFilters.onlyCustomImage;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _commitPending() {
    if (_applied) return;
    _applied = true;
    widget.onApply(
      FossilCatalogFilters(
        searchQuery: _pendingSearch.trim(),
        maYounger: _pendingRange.start,
        maOlder: _pendingRange.end,
        onlyCustomImage: _pendingOnlyCustomImage,
      ),
    );
  }

  FossilCatalogFilters _buildPendingFilters() {
    return FossilCatalogFilters(
      searchQuery: _pendingSearch.trim(),
      maYounger: _pendingRange.start,
      maOlder: _pendingRange.end,
      onlyCustomImage: _pendingOnlyCustomImage,
    );
  }

  void _clearPending() {
    setState(() {
      _pendingSearch = '';
      _searchController.clear();
      _pendingRange = const RangeValues(
        GeologicTimeline.mesozoicYoungerMa,
        GeologicTimeline.mesozoicOlderMa,
      );
      _pendingOnlyCustomImage = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final divisions =
        (GeologicTimeline.mesozoicOlderMa - GeologicTimeline.mesozoicYoungerMa)
            .round();

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _commitPending();
      },
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: DrawerSheetSizes.initialChildSize,
        minChildSize: DrawerSheetSizes.minChildSize,
        maxChildSize: DrawerSheetSizes.maxChildSize,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filter',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (widget.catalogTotal != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${widget.catalogTotal} fossils in catalog',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              _buildSearchField(context),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _pendingOnlyCustomImage,
                onChanged: (value) {
                  setState(() => _pendingOnlyCustomImage = value ?? true);
                },
                title: const Text('Custom image only'),
                subtitle: Text(
                  'Only show fossils whose dinosaur has a custom card image',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Time range',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Showing ${_pendingRange.end.round()} – ${_pendingRange.start.round()} Ma',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
                child: RangeSlider(
                  values: _pendingRange,
                  min: GeologicTimeline.mesozoicYoungerMa,
                  max: GeologicTimeline.mesozoicOlderMa,
                  divisions: divisions,
                  onChanged: (values) {
                    setState(() => _pendingRange = values);
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${GeologicTimeline.mesozoicOlderMa.round()} Ma',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${GeologicTimeline.mesozoicYoungerMa.round()} Ma',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  TextButton(
                    onPressed: _buildPendingFilters().hasActiveFilters
                        ? _clearPending
                        : null,
                    child: const Text('Clear'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      _commitPending();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _searchController,
        textCapitalization: TextCapitalization.sentences,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        onChanged: (value) => setState(() => _pendingSearch = value),
        decoration: InputDecoration(
          hintText: 'Search fossils…',
          prefixIcon: Icon(
            Icons.search,
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _pendingSearch = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}
