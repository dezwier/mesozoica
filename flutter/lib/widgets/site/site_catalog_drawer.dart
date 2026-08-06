import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/site_catalog_controller.dart';
import '../../models/catalog_data_source.dart';
import '../../models/site.dart';
import '../../models/site_map_filters.dart';
import '../../models/site_type.dart';
import '../../services/site_service.dart';
import '../../theme/dino_card_theme.dart';
import '../../theme/map_chrome_theme.dart';
import '../../utils/curated_image_url.dart';
import '../cards/site_card_dialog.dart';
import '../common/catalog_album_drawer.dart';
import '../common/catalog_album_tile.dart';
import '../map/site_filter_sheet.dart';

/// Catalog album drawer for site types (opened from inventory FAB).
class SiteCatalogDrawer {
  SiteCatalogDrawer._();

  static Future<void> show(BuildContext context) {
    return CatalogAlbumDrawer.show(
      context,
      builder: (scrollController) =>
          _SiteCatalogAlbumBody(scrollController: scrollController),
    );
  }
}

class _SiteCatalogAlbumBody extends StatefulWidget {
  const _SiteCatalogAlbumBody({required this.scrollController});

  final ScrollController scrollController;

  @override
  State<_SiteCatalogAlbumBody> createState() => _SiteCatalogAlbumBodyState();
}

class _SiteCatalogAlbumBodyState extends State<_SiteCatalogAlbumBody> {
  static const _pageSize = 20;

  final SiteService _service = SiteService();

  final List<SiteTypeSummary> _items = [];
  String? _error;
  bool _loading = false;
  bool _hasMore = true;
  int _fetchOffset = 0;
  SiteCatalogController? _catalog;
  SiteMapFilters? _appliedFilters;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _catalog = context.read<SiteCatalogController>();
      _catalog!.addListener(_onCatalogChanged);
      _load(reset: true);
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
    if (_catalogFiltersEqual(catalog.filters, _appliedFilters)) return;
    _load(reset: true);
  }

  bool _catalogFiltersEqual(SiteMapFilters a, SiteMapFilters? b) {
    if (b == null) return false;
    return setEquals(a.periods, b.periods) &&
        setEquals(a.rockTypes, b.rockTypes);
  }

  Future<void> _load({required bool reset}) async {
    if (_loading) return;
    if (!reset && !_hasMore) return;
    final catalog = _catalog ?? context.read<SiteCatalogController>();
    final filters = catalog.filters;
    setState(() {
      _loading = true;
      if (reset) {
        _error = null;
        _items.clear();
        _hasMore = true;
        _fetchOffset = 0;
        _appliedFilters = SiteMapFilters(
          periods: {...filters.periods},
          rockTypes: {...filters.rockTypes},
        );
      }
    });
    try {
      if (reset) {
        await _fillPage(filters: filters, targetCount: _pageSize);
      } else {
        await _fetchNextMatchingPage(filters: filters);
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
    } on SiteServiceException catch (error) {
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

  /// Keep fetching server pages until we have [targetCount] matches or exhaust.
  Future<void> _fillPage({
    required SiteMapFilters filters,
    required int targetCount,
  }) async {
    while (mounted && _hasMore && _items.length < targetCount) {
      final before = _items.length;
      await _fetchNextMatchingPage(filters: filters);
      if (_items.length == before) break;
    }
  }

  Future<void> _fetchNextMatchingPage({required SiteMapFilters filters}) async {
    // When filters are active, skip empty filtered pages until we get matches.
    while (mounted && _hasMore) {
      final response = await _service.fetchSiteTypes(
        limit: _pageSize,
        offset: _fetchOffset,
      );
      final matched = [
        for (final type in response.items)
          if (filters.matchesSiteType(
            period: type.period,
            rockType: type.rockType,
          ))
            type,
      ];
      _fetchOffset += response.items.length;
      _hasMore = response.hasMore;
      if (response.items.isEmpty) {
        _hasMore = false;
      }
      if (!mounted) return;
      if (matched.isNotEmpty) {
        setState(() => _items.addAll(matched));
        return;
      }
      if (!filters.hasActiveCatalogFilters || !_hasMore) {
        return;
      }
    }
  }

  Future<void> _openFilterSheet() async {
    final catalog = context.read<SiteCatalogController>();
    await SiteFilterSheet.show(
      context,
      initialFilters: catalog.filters,
      showSortSection: false,
      showStatusSection: false,
      showDiscoveryTimeSection: false,
      showHowDiscoveredSection: false,
      showReconRoutesSection: false,
      onApply: catalog.applyFilters,
    );
  }

  void _openOccurrence(OwnedOccurrenceThumb thumb) {
    showSiteCardDialog(
      context,
      siteId: thumb.id,
      dataSource: thumb.id >= SiteSummary.fieldSiteIdBase
          ? CatalogDataSource.field
          : CatalogDataSource.archive,
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<SiteCatalogController>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headerColor = isDark
        ? MapChromeTheme.cream
        : MapChromeTheme.brownText;
    final hasActive = catalog.filters.hasActiveCatalogFilters;

    return CatalogAlbumDrawer(
      scrollController: widget.scrollController,
      title: 'Site Catalog',
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
            ? 'No sites match these filters.'
            : 'No sites in the catalog yet.',
        itemBuilder: (context, index) {
          final siteType = _items[index];
          return CatalogAlbumTile(
            imageUrl: siteType.mainImageUrl,
            owned: siteType.isCatalogOwned,
            ownedOccurrences: siteType.ownedOccurrences,
            title: siteType.displayTitle,
            placeholderAsset: DinoCardTheme.sitePlaceholderAsset,
            isCuratedUrl: isCuratedSiteTypeImageUrl,
            onOwnedTap: _openOccurrence,
          );
        },
      ),
    );
  }
}
