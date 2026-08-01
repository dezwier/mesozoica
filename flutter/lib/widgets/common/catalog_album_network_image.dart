import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/catalog_album_cache.dart';
import '../../utils/curated_image_url.dart';
import '../../utils/network_image_mem_cache.dart';

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
        final memW = networkImageMemCacheExtent(constraints.maxWidth, dpr);
        final memH = networkImageMemCacheExtent(constraints.maxHeight, dpr);
        return CachedNetworkImage(
          imageUrl: albumUrl,
          cacheManager: CatalogAlbumCache.instance,
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
