import 'package:flutter/material.dart';

import '../../controllers/dinosaur_catalog_controller.dart';
import '../cards/geologic_timeline.dart';

class DinosaurFilterSheet extends StatefulWidget {
  const DinosaurFilterSheet({
    super.key,
    required this.initialFilters,
    required this.onApply,
    this.catalogTotal,
  });

  final DinosaurCatalogFilters initialFilters;
  final ValueChanged<DinosaurCatalogFilters> onApply;
  final int? catalogTotal;

  static Future<void> show(
    BuildContext context, {
    required DinosaurCatalogFilters initialFilters,
    required ValueChanged<DinosaurCatalogFilters> onApply,
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
      builder: (_) => DinosaurFilterSheet(
        initialFilters: initialFilters,
        onApply: onApply,
        catalogTotal: catalogTotal,
      ),
    );
  }

  @override
  State<DinosaurFilterSheet> createState() => _DinosaurFilterSheetState();
}

class _DinosaurFilterSheetState extends State<DinosaurFilterSheet> {
  late final TextEditingController _searchController;
  late String _pendingSearch;
  late RangeValues _pendingRange;
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
      DinosaurCatalogFilters(
        searchQuery: _pendingSearch.trim(),
        maYounger: _pendingRange.start,
        maOlder: _pendingRange.end,
      ),
    );
  }

  DinosaurCatalogFilters _buildPendingFilters() {
    return DinosaurCatalogFilters(
      searchQuery: _pendingSearch.trim(),
      maYounger: _pendingRange.start,
      maOlder: _pendingRange.end,
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
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.85,
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
                    '${widget.catalogTotal} dinosaurs in catalog',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              _buildSearchField(context),
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
              RangeSlider(
                values: _pendingRange,
                min: GeologicTimeline.mesozoicYoungerMa,
                max: GeologicTimeline.mesozoicOlderMa,
                divisions: divisions,
                labels: RangeLabels(
                  '${_pendingRange.start.round()} Ma',
                  '${_pendingRange.end.round()} Ma',
                ),
                onChanged: (values) {
                  setState(() => _pendingRange = values);
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${GeologicTimeline.mesozoicYoungerMa.round()} Ma',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${GeologicTimeline.mesozoicOlderMa.round()} Ma',
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
          hintText: 'Search dinosaurs…',
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
