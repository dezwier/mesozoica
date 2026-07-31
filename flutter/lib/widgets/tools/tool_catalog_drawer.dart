import 'package:flutter/material.dart';

import '../../models/tool.dart';
import '../../services/tool_service.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/curated_image_url.dart';
import '../cards/tool_card_dialog.dart';
import '../common/catalog_album_drawer.dart';
import '../common/catalog_album_tile.dart';

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
      final response = await _service.fetchTools(
        limit: _pageSize,
        offset: reset ? 0 : _items.length,
        sort: 'category',
        mode: 'catalog',
        showAll: true,
        hasCustomImage: true,
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

  void _openOccurrence(ToolSummary catalogRow, OwnedOccurrenceThumb thumb) {
    final occurrence = catalogRow.occurrenceFromThumb(thumb);
    showToolCardDialog(context, tool: occurrence);
  }

  @override
  Widget build(BuildContext context) {
    return CatalogAlbumDrawer(
      scrollController: widget.scrollController,
      title: 'Tool Catalog',
      body: CatalogAlbumGrid(
        scrollController: widget.scrollController,
        itemCount: _items.length,
        hasMore: _hasMore,
        isLoading: _loading,
        errorMessage: _error,
        onRetry: () => _load(reset: true),
        onLoadMore: () => _load(reset: false),
        emptyMessage: 'No tools in the catalog yet.',
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
          );
        },
      ),
    );
  }
}
