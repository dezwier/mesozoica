import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/tool_catalog_controller.dart';
import '../../models/tool.dart';
import '../../services/tool_service.dart';
import '../../theme/dino_card_theme.dart';
import '../../theme/map_chrome_theme.dart';
import '../../utils/curated_image_url.dart';
import '../cards/tool_card_dialog.dart';
import '../common/catalog_album_drawer.dart';
import '../common/catalog_album_tile.dart';
import '../common/catalog_collect_flow.dart';
import 'filters/tool_filter_sheet.dart';

/// Catalog album drawer for tool types (opened from inventory FAB).
class ToolCatalogDrawer {
  ToolCatalogDrawer._();

  static Future<void> show(BuildContext context) {
    return CatalogAlbumDrawer.show(
      context,
      builder: (scrollController) => _ToolCatalogAlbumBody(
        scrollController: scrollController,
      ),
    );
  }
}

class _ToolCatalogAlbumBody extends StatefulWidget {
  const _ToolCatalogAlbumBody({required this.scrollController});

  final ScrollController scrollController;

  @override
  State<_ToolCatalogAlbumBody> createState() => _ToolCatalogAlbumBodyState();
}

class _ToolCatalogAlbumBodyState extends State<_ToolCatalogAlbumBody> {
  static const _pageSize = 60;

  final ToolService _service = ToolService();

  final List<ToolSummary> _items = [];
  String? _error;
  bool _loading = false;
  bool _hasMore = true;
  ToolCatalogController? _catalog;
  ToolCatalogFilters? _appliedFilters;
  List<ToolCategoryOption> _catalogCategories = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _catalog = context.read<ToolCatalogController>();
      _catalog!.addListener(_onCatalogChanged);
      _load(reset: true);
      unawaited(_loadCatalogCategories());
    });
  }

  @override
  void dispose() {
    _catalog?.removeListener(_onCatalogChanged);
    _service.dispose();
    super.dispose();
  }

  void _onCatalogChanged() {
    final catalog = _catalog;
    if (catalog == null || !mounted) return;
    if (_filtersEqual(catalog.filters, _appliedFilters)) return;
    _load(reset: true);
  }

  bool _filtersEqual(ToolCatalogFilters a, ToolCatalogFilters? b) {
    if (b == null) return false;
    return a.searchQuery == b.searchQuery &&
        a.sort == b.sort &&
        setEquals(a.categories, b.categories);
  }

  ToolCatalogSort _catalogSort(ToolCatalogFilters filters) {
    final options = ToolCatalogSort.optionsFor(ToolScreenMode.catalog);
    return options.contains(filters.sort)
        ? filters.sort
        : ToolCatalogSort.category;
  }

  Future<void> _loadCatalogCategories() async {
    try {
      final categories = await _service.fetchCategories(
        showAll: true,
        mode: 'catalog',
      );
      if (!mounted) return;
      setState(() => _catalogCategories = categories);
    } catch (_) {
      // Fall back to inventory categories from the controller when needed.
    }
  }

  Future<void> _load({required bool reset}) async {
    if (_loading) return;
    if (!reset && !_hasMore) return;
    final catalog = _catalog ?? context.read<ToolCatalogController>();
    final filters = catalog.filters;
    final sort = _catalogSort(filters);
    setState(() {
      _loading = true;
      if (reset) {
        _error = null;
        _items.clear();
        _hasMore = true;
        _appliedFilters = filters;
      }
    });
    try {
      final trimmedQuery = filters.searchQuery.trim();
      final response = await _service.fetchTools(
        limit: _pageSize,
        offset: reset ? 0 : _items.length,
        sort: sort.apiValue,
        mode: 'catalog',
        showAll: true,
        hasCustomImage: true,
        q: trimmedQuery.isNotEmpty ? trimmedQuery : null,
        categories: filters.categories,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(response.items);
        _hasMore = response.hasMore;
        _loading = false;
        _error = null;
      });
    } on ToolServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load catalog.';
      });
    }
  }

  Future<void> _openFilterSheet() async {
    final catalog = context.read<ToolCatalogController>();
    final categories = _catalogCategories.isNotEmpty
        ? _catalogCategories
        : catalog.availableCategories;
    await ToolFilterSheet.show(
      context,
      initialFilters: catalog.filters,
      mode: ToolScreenMode.catalog,
      catalogTotal: catalog.total > 0 ? catalog.total : null,
      availableCategories: categories,
      onApply: catalog.applyFilters,
    );
  }

  void _openOccurrence(ToolSummary catalogRow, OwnedOccurrenceThumb thumb) {
    final occurrence = catalogRow.occurrenceFromThumb(thumb);
    showToolCardDialog(context, tool: occurrence);
  }

  Future<void> _collectOccurrence(ToolSummary catalogRow) async {
    final typeId = catalogRow.toolTypeId ?? catalogRow.id;
    final created = await CatalogCollectFlow.collectTool(
      context,
      toolTypeId: typeId,
    );
    if (!mounted || created == null) return;
    final index = _items.indexWhere((item) => item.id == catalogRow.id);
    if (index < 0) return;
    setState(() {
      _items[index] = _items[index].withAddedOwnedOccurrence(created);
    });
    context.read<ToolCatalogController>().load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<ToolCatalogController>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headerColor =
        isDark ? MapChromeTheme.cream : MapChromeTheme.brownText;
    final hasActive =
        catalog.filters.hasActiveFiltersFor(ToolScreenMode.catalog);

    return CatalogAlbumDrawer(
      scrollController: widget.scrollController,
      title: 'Tool Catalog',
      leading: IconButton(
        tooltip: 'Filter',
        onPressed: _openFilterSheet,
        icon: Badge(
          isLabelVisible: hasActive,
          smallSize: 8,
          backgroundColor: MapChromeTheme.goldBright,
          child: Icon(
            Icons.filter_list,
            color: headerColor.withValues(alpha: 0.75),
          ),
        ),
      ),
      body: CatalogAlbumGrid(
        scrollController: widget.scrollController,
        itemCount: _items.length,
        hasMore: _hasMore,
        isLoading: _loading,
        errorMessage: _error,
        onRetry: () => _load(reset: true),
        onLoadMore: () => _load(reset: false),
        emptyMessage: hasActive
            ? 'No tools match these filters.'
            : 'No tools in the catalog yet.',
        itemBuilder: (context, index) {
          final tool = _items[index];
          return CatalogAlbumTile(
            imageUrl: tool.mainImageUrl,
            owned: tool.isCatalogOwned,
            ownedOccurrences: tool.ownedOccurrences,
            title: tool.name,
            placeholderAsset: DinoCardTheme.sitePlaceholderAsset,
            isCuratedUrl: isCuratedToolImageUrl,
            onOwnedTap: (thumb) => _openOccurrence(tool, thumb),
            onAdminCollect: () => _collectOccurrence(tool),
          );
        },
      ),
    );
  }
}
