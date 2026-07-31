import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../utils/curated_image_url.dart';

/// Catalog album tile network image: album WebP only (never full card art).
class CatalogAlbumNetworkImage extends StatelessWidget {
  const CatalogAlbumNetworkImage({
    super.key,
    required this.fullUrl,
    required this.placeholder,
    required this.errorWidget,
    this.imageBuilder,
  });

  /// Full curated card URL from the API; used only to derive the album thumb URL.
  final String fullUrl;
  final Widget placeholder;
  final Widget errorWidget;
  final Widget Function(BuildContext context, ImageProvider provider)?
      imageBuilder;

  @override
  Widget build(BuildContext context) {
    final albumUrl = albumImageUrlFromCurated(fullUrl);
    if (albumUrl == null) {
      return errorWidget;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final memW = _memCacheExtent(constraints.maxWidth, dpr);
        final memH = _memCacheExtent(constraints.maxHeight, dpr);
        return CachedNetworkImage(
          imageUrl: albumUrl,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          placeholderFadeInDuration: Duration.zero,
          memCacheWidth: memW,
          memCacheHeight: memH,
          httpHeaders: const {
            'User-Agent': 'Mesozoica/1.0 (mobile app; catalog album)',
          },
          imageBuilder: imageBuilder,
          placeholder: (context, url) => placeholder,
          errorWidget: (context, url, error) => errorWidget,
        );
      },
    );
  }
}

int _memCacheExtent(double logicalPx, double dpr) {
  if (!logicalPx.isFinite || logicalPx <= 0) {
    return (128 * dpr).round().clamp(1, 2048);
  }
  return (logicalPx * dpr).round().clamp(1, 2048);
}
