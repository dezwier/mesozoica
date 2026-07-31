import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../services/dinosaur_service.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/curated_image_url.dart';
import '../cards/dinosaur_card_dialog.dart';
import '../common/catalog_album_drawer.dart';
import '../common/catalog_album_tile.dart';

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
      final response = await _service.fetchDinosaurs(
        limit: _pageSize,
        offset: reset ? 0 : _items.length,
        sort: 'name',
        mode: 'catalog',
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(response.items);
        _total = response.total;
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

  void _openOccurrence(DinosaurSummary catalogRow, OwnedOccurrenceThumb thumb) {
    final occurrence = catalogRow.occurrenceFromThumb(thumb);
    showDinosaurCardDialog(context, dinosaur: occurrence);
  }

  @override
  Widget build(BuildContext context) {
    return CatalogAlbumDrawer(
      scrollController: widget.scrollController,
      title: 'Dinosaur Catalog',
      body: CatalogAlbumGrid(
        scrollController: widget.scrollController,
        itemCount: _items.length,
        hasMore: _hasMore,
        isLoading: _loading,
        errorMessage: _error,
        onRetry: () => _load(reset: true),
        onLoadMore: () => _load(reset: false),
        emptyMessage: _total == 0 && !_loading
            ? 'No dinosaurs in the catalog yet.'
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
          );
        },
      ),
    );
  }
}
