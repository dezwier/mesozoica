import 'package:flutter/material.dart';

import '../../models/catalog_data_source.dart';
import '../../models/site.dart';
import '../../models/site_type.dart';
import '../../services/site_service.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/curated_image_url.dart';
import '../cards/site_card_dialog.dart';
import '../common/catalog_album_drawer.dart';
import '../common/catalog_album_tile.dart';

/// Catalog album drawer for site types (opened from inventory FAB).
class SiteCatalogDrawer {
  SiteCatalogDrawer._();

  static Future<void> show(BuildContext context) {
    return CatalogAlbumDrawer.show(
      context,
      builder: (scrollController) => _SiteCatalogAlbumBody(
        scrollController: scrollController,
      ),
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
  static const _pageSize = 60;

  final SiteService _service = SiteService();

  final List<SiteTypeSummary> _items = [];
  String? _error;
  bool _loading = false;
  bool _hasMore = true;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    if (_loading) return;
    if (!reset && !_hasMore) return;
    setState(() {
      _loading = true;
      if (reset) {
        _error = null;
        _items.clear();
        _hasMore = true;
      }
    });
    try {
      final response = await _service.fetchSiteTypes(
        limit: _pageSize,
        offset: reset ? 0 : _items.length,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(response.items);
        _total = response.total;
        _hasMore = response.hasMore;
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
    return CatalogAlbumDrawer(
      scrollController: widget.scrollController,
      title: 'Site Catalog',
      body: CatalogAlbumGrid(
        scrollController: widget.scrollController,
        itemCount: _items.length,
        hasMore: _hasMore,
        isLoading: _loading,
        errorMessage: _error,
        onRetry: () => _load(reset: true),
        onLoadMore: () => _load(reset: false),
        emptyMessage: _total == 0 && !_loading
            ? 'No sites in the catalog yet.'
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
