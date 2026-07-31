import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/owned_occurrence_thumb.dart';
import '../../theme/dino_card_theme.dart';
import '../../theme/map_chrome_theme.dart';
import '../../utils/curated_image_url.dart';
import 'catalog_silhouette_image.dart';

/// Compact catalog-album cell: silhouette when locked, color gallery when owned.
class CatalogAlbumTile extends StatefulWidget {
  const CatalogAlbumTile({
    super.key,
    required this.imageUrl,
    required this.owned,
    required this.ownedOccurrences,
    required this.placeholderAsset,
    required this.isCuratedUrl,
    this.onOwnedTap,
  });

  final String? imageUrl;
  final bool owned;
  final List<OwnedOccurrenceThumb> ownedOccurrences;
  final String placeholderAsset;
  final bool Function(String? url) isCuratedUrl;
  final ValueChanged<OwnedOccurrenceThumb>? onOwnedTap;

  @override
  State<CatalogAlbumTile> createState() => CatalogAlbumTileState();
}

class CatalogAlbumTileState extends State<CatalogAlbumTile> {
  late final PageController _pageController;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  OwnedOccurrenceThumb? get visibleOccurrence {
    final owned = widget.ownedOccurrences;
    if (owned.isEmpty) return null;
    final index = _pageIndex.clamp(0, owned.length - 1);
    return owned[index];
  }

  void _handleTap() {
    if (!widget.owned) return;
    final thumb = visibleOccurrence ??
        (widget.ownedOccurrences.isNotEmpty
            ? widget.ownedOccurrences.first
            : null);
    if (thumb == null) return;
    widget.onOwnedTap?.call(thumb);
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(DinoCardTheme.borderRadius * 0.55);
    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Material(
        color: CatalogSilhouetteImage.ground,
        elevation: widget.owned ? 2 : 0,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: MapChromeTheme.parchmentEdge.withValues(alpha: 0.9),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.owned ? _handleTap : null,
          child: widget.owned
              ? _OwnedGallery(
                  occurrences: widget.ownedOccurrences,
                  fallbackImageUrl: widget.imageUrl,
                  placeholderAsset: widget.placeholderAsset,
                  isCuratedUrl: widget.isCuratedUrl,
                  controller: _pageController,
                  pageIndex: _pageIndex,
                  onPageChanged: (index) {
                    setState(() => _pageIndex = index);
                  },
                )
              : CatalogSilhouetteImage(
                  imageUrl: widget.imageUrl,
                  placeholderAsset: widget.placeholderAsset,
                  isCuratedUrl: widget.isCuratedUrl,
                ),
        ),
      ),
    );
  }
}

class _OwnedGallery extends StatelessWidget {
  const _OwnedGallery({
    required this.occurrences,
    required this.fallbackImageUrl,
    required this.placeholderAsset,
    required this.isCuratedUrl,
    required this.controller,
    required this.pageIndex,
    required this.onPageChanged,
  });

  final List<OwnedOccurrenceThumb> occurrences;
  final String? fallbackImageUrl;
  final String placeholderAsset;
  final bool Function(String? url) isCuratedUrl;
  final PageController controller;
  final int pageIndex;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    if (occurrences.isEmpty) {
      return _ColorImage(
        imageUrl: fallbackImageUrl,
        placeholderAsset: placeholderAsset,
        isCuratedUrl: isCuratedUrl,
      );
    }
    if (occurrences.length == 1) {
      return _ColorImage(
        imageUrl: occurrences.first.mainImageUrl ?? fallbackImageUrl,
        placeholderAsset: placeholderAsset,
        isCuratedUrl: isCuratedUrl,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: controller,
          onPageChanged: onPageChanged,
          itemCount: occurrences.length,
          itemBuilder: (context, index) {
            final thumb = occurrences[index];
            return _ColorImage(
              imageUrl: thumb.mainImageUrl ?? fallbackImageUrl,
              placeholderAsset: placeholderAsset,
              isCuratedUrl: isCuratedUrl,
            );
          },
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 6,
          child: IgnorePointer(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(occurrences.length, (index) {
                return Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(
                      alpha: index == pageIndex ? 0.95 : 0.45,
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}

class _ColorImage extends StatelessWidget {
  const _ColorImage({
    required this.imageUrl,
    required this.placeholderAsset,
    required this.isCuratedUrl,
  });

  final String? imageUrl;
  final String placeholderAsset;
  final bool Function(String? url) isCuratedUrl;

  @override
  Widget build(BuildContext context) {
    final curated = isCuratedUrl(imageUrl) ? imageUrl!.trim() : null;
    if (curated == null) {
      return Image.asset(placeholderAsset, fit: BoxFit.cover);
    }
    return CachedNetworkImage(
      imageUrl: curated,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      httpHeaders: const {
        'User-Agent': 'Mesozoica/1.0 (mobile app; catalog album)',
      },
      placeholder: (context, url) =>
          const ColoredBox(color: CatalogSilhouetteImage.ground),
      errorWidget: (context, url, error) =>
          Image.asset(placeholderAsset, fit: BoxFit.cover),
    );
  }
}

/// Convenience: dinosaur curated URL check.
bool catalogIsDinosaurImageUrl(String? url) => isCuratedDinosaurImageUrl(url);

/// Convenience: tool curated URL check.
bool catalogIsToolImageUrl(String? url) => isCuratedToolImageUrl(url);
