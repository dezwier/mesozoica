import 'package:flutter/material.dart';

import '../../controllers/tool_catalog_controller.dart';
import '../../models/tool.dart';
import '../common/drawer_sheet_sizes.dart';

class ToolFilterSheet extends StatefulWidget {
  const ToolFilterSheet({
    super.key,
    required this.initialFilters,
    required this.onApply,
    this.catalogTotal,
    this.availableCategories = const [],
    this.isAdmin = false,
  });

  final ToolCatalogFilters initialFilters;
  final ValueChanged<ToolCatalogFilters> onApply;
  final int? catalogTotal;
  final List<ToolCategoryOption> availableCategories;
  final bool isAdmin;

  static Future<void> show(
    BuildContext context, {
    required ToolCatalogFilters initialFilters,
    required ValueChanged<ToolCatalogFilters> onApply,
    int? catalogTotal,
    List<ToolCategoryOption> availableCategories = const [],
    bool isAdmin = false,
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
      builder: (_) => ToolFilterSheet(
        initialFilters: initialFilters,
        onApply: onApply,
        catalogTotal: catalogTotal,
        availableCategories: availableCategories,
        isAdmin: isAdmin,
      ),
    );
  }

  @override
  State<ToolFilterSheet> createState() => _ToolFilterSheetState();
}

class _ToolFilterSheetState extends State<ToolFilterSheet> {
  late final TextEditingController _searchController;
  late String _pendingSearch;
  late ToolCatalogSort _pendingSort;
  late Set<String> _pendingCategories;
  late bool _pendingShowAll;
  bool _applied = false;

  @override
  void initState() {
    super.initState();
    _pendingSearch = widget.initialFilters.searchQuery;
    _pendingSort = widget.initialFilters.sort;
    _pendingCategories = {...widget.initialFilters.categories};
    _pendingShowAll = widget.initialFilters.showAll;
    _searchController = TextEditingController(text: _pendingSearch);
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
      ToolCatalogFilters(
        searchQuery: _pendingSearch.trim(),
        sort: _pendingSort,
        categories: {..._pendingCategories},
        showAll: widget.isAdmin && _pendingShowAll,
      ),
    );
  }

  ToolCatalogFilters _buildPendingFilters() {
    return ToolCatalogFilters(
      searchQuery: _pendingSearch.trim(),
      sort: _pendingSort,
      categories: {..._pendingCategories},
      showAll: widget.isAdmin && _pendingShowAll,
    );
  }

  void _clearPending() {
    setState(() {
      _pendingSearch = '';
      _pendingSort = ToolCatalogSort.category;
      _pendingCategories = {};
      _pendingShowAll = false;
      _searchController.clear();
    });
  }

  void _toggleCategory(String value, bool? selected) {
    setState(() {
      if (selected ?? false) {
        _pendingCategories.add(value);
      } else {
        _pendingCategories.remove(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                    '${widget.catalogTotal} tools in catalog',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              _buildSearchField(
                context,
                controller: _searchController,
                hintText: 'Search tool name…',
                onChanged: (value) => setState(() => _pendingSearch = value),
                onClear: () {
                  _searchController.clear();
                  setState(() => _pendingSearch = '');
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Sort',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _buildSortDropdown(context),
              if (widget.isAdmin) ...[
                const SizedBox(height: 16),
                Text(
                  'Admin',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _checkboxTile(
                  theme: theme,
                  value: _pendingShowAll,
                  label: 'Show all tools',
                  onChanged: (selected) =>
                      setState(() => _pendingShowAll = selected ?? false),
                ),
              ],
              if (widget.availableCategories.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Category',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ...widget.availableCategories.map(
                  (option) => _checkboxTile(
                    theme: theme,
                    value: _pendingCategories.contains(option.value),
                    label: option.label,
                    onChanged: (selected) =>
                        _toggleCategory(option.value, selected),
                  ),
                ),
              ],
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

  Widget _buildSearchField(
    BuildContext context, {
    required TextEditingController controller,
    required String hintText,
    required ValueChanged<String> onChanged,
    required VoidCallback onClear,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        textCapitalization: TextCapitalization.sentences,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: Icon(
            Icons.search,
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  onPressed: onClear,
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

  Widget _buildSortDropdown(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ToolCatalogSort>(
          value: _pendingSort,
          isExpanded: true,
          icon: Icon(
            Icons.expand_more,
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _pendingSort = value);
          },
          items: ToolCatalogSort.values
              .map(
                (sort) => DropdownMenuItem(
                  value: sort,
                  child: Text(sort.label),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _checkboxTile({
    required ThemeData theme,
    required bool value,
    required String label,
    required ValueChanged<bool?> onChanged,
  }) {
    return SizedBox(
      height: 44,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 44,
              child: IgnorePointer(
                child: Checkbox(
                  value: value,
                  onChanged: (_) {},
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity:
                      const VisualDensity(horizontal: -4, vertical: -4),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
