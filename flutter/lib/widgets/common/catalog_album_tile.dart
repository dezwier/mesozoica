import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/owned_occurrence_thumb.dart';
import '../../theme/dino_card_theme.dart';
import '../../theme/map_chrome_theme.dart';
import '../cards/card_adaptive_title_text.dart';
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
    this.title,
    this.onOwnedTap,
  });

  final String? imageUrl;
  final bool owned;
  final List<OwnedOccurrenceThumb> ownedOccurrences;
  final String placeholderAsset;
  final bool Function(String? url) isCuratedUrl;

  /// Shown on owned tiles only (bottom center, width-fitted).
  final String? title;
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
                  title: widget.title,
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
    this.title,
  });

  final List<OwnedOccurrenceThumb> occurrences;
  final String? fallbackImageUrl;
  final String placeholderAsset;
  final bool Function(String? url) isCuratedUrl;
  final PageController controller;
  final int pageIndex;
  final ValueChanged<int> onPageChanged;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final image = _buildImage();
    final label = title?.trim();
    final showTitle = label != null && label.isNotEmpty;
    final multi = occurrences.length > 1;

    if (!showTitle && !multi) return image;

    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        Positioned(
          left: 5,
          right: 5,
          bottom: 6,
          child: IgnorePointer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (multi) ...[
                  Row(
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
                  if (showTitle) const SizedBox(height: 4),
                ],
                if (showTitle)
                  CardAdaptiveTitleText(
                    text: label,
                    textAlign: TextAlign.center,
                    style: DinoCardTheme.dark.frontOverlayTitleStyle(
                      fontSize: 13,
                    ).copyWith(
                      fontFamily: MapChromeTheme.serifFont,
                      letterSpacing: 0.4,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImage() {
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
    return PageView.builder(
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
