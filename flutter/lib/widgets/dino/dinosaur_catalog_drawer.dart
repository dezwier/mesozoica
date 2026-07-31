import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/dinosaur_catalog_controller.dart';
import '../../models/dinosaur.dart';
import '../../services/dinosaur_service.dart';
import '../../theme/dino_card_theme.dart';
import '../../theme/map_chrome_theme.dart';
import '../../utils/curated_image_url.dart';
import '../cards/dinosaur_card_dialog.dart';
import '../common/catalog_album_drawer.dart';
import '../common/catalog_album_tile.dart';
import '../common/catalog_collect_flow.dart';
import 'dinosaur_filter_sheet.dart';

/// Catalog album drawer for dinosaur types (opened from inventory FAB).
class DinosaurCatalogDrawer {
  DinosaurCatalogDrawer._();

  static Future<void> show(BuildContext context) {
    return CatalogAlbumDrawer.show(
      context,
      builder: (scrollController) => _DinosaurCatalogAlbumBody(
        scrollController: scrollController,
      ),
    );
  }
}

class _DinosaurCatalogAlbumBody extends StatefulWidget {
  const _DinosaurCatalogAlbumBody({required this.scrollController});

  final ScrollController scrollController;

  @override
  State<_DinosaurCatalogAlbumBody> createState() =>
      _DinosaurCatalogAlbumBodyState();
}

class _DinosaurCatalogAlbumBodyState extends State<_DinosaurCatalogAlbumBody> {
  static const _pageSize = 60;

  final DinosaurService _service = DinosaurService();

  final List<DinosaurSummary> _items = [];
  String? _error;
  bool _loading = false;
  bool _hasMore = true;
  DinosaurCatalogController? _catalog;
  DinosaurCatalogFilters? _appliedFilters;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _catalog = context.read<DinosaurCatalogController>();
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
    if (_filtersEqual(catalog.filters, _appliedFilters)) return;
    _load(reset: true);
  }

  bool _filtersEqual(DinosaurCatalogFilters a, DinosaurCatalogFilters? b) {
    if (b == null) return false;
    return a.searchQuery == b.searchQuery &&
        a.maYounger == b.maYounger &&
        a.maOlder == b.maOlder &&
        a.lengthMMin == b.lengthMMin &&
        a.lengthMMax == b.lengthMMax &&
        a.massKgMin == b.massKgMin &&
        a.massKgMax == b.massKgMax &&
        setEquals(a.diets, b.diets);
  }

  Future<void> _load({required bool reset}) async {
    if (_loading) return;
    if (!reset && !_hasMore) return;
    final catalog = _catalog ?? context.read<DinosaurCatalogController>();
    final filters = catalog.filters;
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
      final hasSearch = filters.searchQuery.trim().isNotEmpty;
      final response = await _service.fetchDinosaurs(
        limit: _pageSize,
        offset: reset ? 0 : _items.length,
        sort: 'name',
        mode: 'catalog',
        q: hasSearch ? filters.searchQuery.trim() : null,
        maYounger: !hasSearch && filters.hasTimeFilter ? filters.maYounger : null,
        maOlder: !hasSearch && filters.hasTimeFilter ? filters.maOlder : null,
        diets: filters.diets,
        lengthMMin: filters.hasLengthFilter ? filters.lengthMMin : null,
        lengthMMax: filters.hasLengthFilter ? filters.lengthMMax : null,
        massKgMin: filters.hasMassFilter ? filters.massKgMin : null,
        massKgMax: filters.hasMassFilter ? filters.massKgMax : null,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(response.items);
        _hasMore = response.hasMore;
        _loading = false;
        _error = null;
      });
    } on DinosaurServiceException catch (error) {
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
    final catalog = context.read<DinosaurCatalogController>();
    await DinosaurFilterSheet.show(
      context,
      initialFilters: catalog.filters,
      catalogTotal: catalog.total,
      onApply: catalog.applyFilters,
    );
  }

  void _openOccurrence(DinosaurSummary catalogRow, OwnedOccurrenceThumb thumb) {
    final occurrence = catalogRow.occurrenceFromThumb(thumb);
    showDinosaurCardDialog(context, dinosaur: occurrence);
  }

  Future<void> _collectOccurrence(DinosaurSummary catalogRow) async {
    final typeId = catalogRow.dinosaurTypeId ?? catalogRow.id;
    final created = await CatalogCollectFlow.collectDinosaur(
      context,
      dinosaurTypeId: typeId,
    );
    if (!mounted || created == null) return;
    final index = _items.indexWhere((item) => item.id == catalogRow.id);
    if (index < 0) return;
    setState(() {
      _items[index] = _items[index].withAddedOwnedOccurrence(created);
    });
    // Keep inventory Cover Flow in sync under the drawer.
    context.read<DinosaurCatalogController>().load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<DinosaurCatalogController>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headerColor =
        isDark ? MapChromeTheme.cream : MapChromeTheme.brownText;
    final hasActive = catalog.hasActiveFilters;

    return CatalogAlbumDrawer(
      scrollController: widget.scrollController,
      title: 'Dinosaur Catalog',
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
            ? 'No dinosaurs match these filters.'
            : 'No dinosaurs in the catalog yet.',
        itemBuilder: (context, index) {
          final dino = _items[index];
          return CatalogAlbumTile(
            imageUrl: dino.mainImageUrl,
            owned: dino.isCatalogOwned,
            ownedOccurrences: dino.ownedOccurrences,
            title: dino.name,
            placeholderAsset: DinoCardTheme.frontPlaceholderAsset,
            isCuratedUrl: isCuratedDinosaurImageUrl,
            onOwnedTap: (thumb) => _openOccurrence(dino, thumb),
            onAdminCollect: () => _collectOccurrence(dino),
          );
        },
      ),
    );
  }
}
