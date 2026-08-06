import 'package:flutter/material.dart';

import '../../../controllers/tool_catalog_controller.dart';
import '../../../models/tool.dart';
import '../../common/drawer_sheet_sizes.dart';
import '../../profile/settings_form_styles.dart';

class ToolFilterSheet extends StatefulWidget {
  const ToolFilterSheet({
    super.key,
    required this.initialFilters,
    required this.onApply,
    this.mode = ToolScreenMode.inventory,
    this.catalogTotal,
    this.availableCategories = const [],
  });

  final ToolCatalogFilters initialFilters;
  final ValueChanged<ToolCatalogFilters> onApply;
  final ToolScreenMode mode;
  final int? catalogTotal;
  final List<ToolCategoryOption> availableCategories;

  static Future<void> show(
    BuildContext context, {
    required ToolCatalogFilters initialFilters,
    required ValueChanged<ToolCatalogFilters> onApply,
    ToolScreenMode mode = ToolScreenMode.inventory,
    int? catalogTotal,
    List<ToolCategoryOption> availableCategories = const [],
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
        mode: mode,
        catalogTotal: catalogTotal,
        availableCategories: availableCategories,
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
  bool _applied = false;

  /// When opening catalog with inventory-only sort (obtain date), keep that
  /// sort on apply unless the user picks a catalog-visible sort.
  bool _preserveInventoryOnlySort = false;

  @override
  void initState() {
    super.initState();
    _pendingSearch = widget.initialFilters.searchQuery;
    final sortOptions = ToolCatalogSort.optionsFor(widget.mode);
    if (sortOptions.contains(widget.initialFilters.sort)) {
      _pendingSort = widget.initialFilters.sort;
      _preserveInventoryOnlySort = false;
    } else {
      _pendingSort = ToolCatalogSort.defaultFor(widget.mode);
      _preserveInventoryOnlySort = true;
    }
    _pendingCategories = {...widget.initialFilters.categories};
    _searchController = TextEditingController(text: _pendingSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleCategory(String value, bool selected) {
    setState(() {
      if (_pendingCategories.isEmpty) {
        _pendingCategories = {
          for (final option in widget.availableCategories) option.value,
        };
      }
      if (selected) {
        _pendingCategories.add(value);
      } else {
        _pendingCategories.remove(value);
      }
    });
  }

  Set<String> _categoriesForApply() {
    if (_pendingCategories.isEmpty) return {};
    final allValues = {
      for (final option in widget.availableCategories) option.value,
    };
    if (_pendingCategories.length == allValues.length &&
        _pendingCategories.containsAll(allValues)) {
      return {};
    }
    return {..._pendingCategories};
  }

  void _commitPending() {
    if (_applied) return;
    _applied = true;
    widget.onApply(
      ToolCatalogFilters(
        searchQuery: _pendingSearch.trim(),
        sort: _resolveSortForApply(),
        categories: _categoriesForApply(),
        showAll: false,
      ),
    );
  }

  ToolCatalogSort _resolveSortForApply() {
    if (_preserveInventoryOnlySort) {
      return widget.initialFilters.sort;
    }
    return _pendingSort;
  }

  ToolCatalogFilters _buildPendingFilters() {
    return ToolCatalogFilters(
      searchQuery: _pendingSearch.trim(),
      sort: _resolveSortForApply(),
      categories: _categoriesForApply(),
      showAll: false,
    );
  }

  void _clearPending() {
    setState(() {
      _pendingSearch = '';
      _pendingSort = ToolCatalogSort.defaultFor(widget.mode);
      _pendingCategories = {};
      _preserveInventoryOnlySort = false;
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final outlineBorder = SettingsFormStyles.outlineBorder(context);
    final categoryOptions = widget.availableCategories;

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
              const SizedBox(height: 20),
              SettingsFormStyles.settingsRow(
                context: context,
                label: 'Sort',
                description: 'Order tools in the catalog list.',
                controlWidth: 168,
                control: SettingsFormStyles.densePopupField<ToolCatalogSort>(
                  context: context,
                  outlineBorder: outlineBorder,
                  selectedChild: Text(
                    _pendingSort.label,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  entries: [
                    for (final sort in ToolCatalogSort.optionsFor(widget.mode))
                      DensePopupEntry(
                        value: sort,
                        child: Text(
                          sort.label,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                  ],
                  onSelected: (value) {
                    if (value == null) return;
                    setState(() {
                      _pendingSort = value;
                      _preserveInventoryOnlySort = false;
                    });
                  },
                ),
              ),
              if (categoryOptions.isNotEmpty) ...[
                const SizedBox(height: 20),
                SettingsFormStyles.settingsRow(
                  context: context,
                  label: 'Category',
                  description: 'Limit tools to one or more categories.',
                  controlWidth: 168,
                  control: SettingsFormStyles.multiSelectDensePopup(
                    context: context,
                    outlineBorder: outlineBorder,
                    selectedChild: Text(
                      SettingsFormStyles.multiSelectSummary(
                        selectedCount: _pendingCategories.isEmpty
                            ? categoryOptions.length
                            : _pendingCategories.length,
                        totalCount: categoryOptions.length,
                      ),
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    entries: [
                      for (final option in categoryOptions)
                        MultiSelectPopupEntry(
                          value: option.value,
                          label: option.label,
                          selected:
                              _pendingCategories.isEmpty ||
                              _pendingCategories.contains(option.value),
                        ),
                    ],
                    onToggle: (value, selected) {
                      _toggleCategory(value, selected);
                    },
                    onSelectOnly: (value) {
                      setState(() => _pendingCategories = {value});
                    },
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  TextButton(
                    onPressed:
                        _buildPendingFilters().hasActiveFiltersFor(widget.mode)
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
              if (categoryOptions.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Long-press an option in a multi-select menu to keep only that one.',
                  style: SettingsFormStyles.finePrintStyle(context),
                ),
              ],
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
}
