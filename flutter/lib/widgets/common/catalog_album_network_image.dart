import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../utils/curated_image_url.dart';

/// Catalog album tile network image: prefers album WebP, falls back to full art.
class CatalogAlbumNetworkImage extends StatefulWidget {
  const CatalogAlbumNetworkImage({
    super.key,
    required this.fullUrl,
    required this.placeholder,
    required this.errorWidget,
    this.imageBuilder,
  });

  final String fullUrl;
  final Widget placeholder;
  final Widget errorWidget;
  final Widget Function(BuildContext context, ImageProvider provider)?
      imageBuilder;

  @override
  State<CatalogAlbumNetworkImage> createState() =>
      _CatalogAlbumNetworkImageState();
}

class _CatalogAlbumNetworkImageState extends State<CatalogAlbumNetworkImage> {
  late bool _useAlbum;
  late String? _albumUrl;

  @override
  void initState() {
    super.initState();
    _albumUrl = albumImageUrlFromCurated(widget.fullUrl);
    _useAlbum = _albumUrl != null && _albumUrl != widget.fullUrl;
  }

  @override
  void didUpdateWidget(covariant CatalogAlbumNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullUrl != widget.fullUrl) {
      _albumUrl = albumImageUrlFromCurated(widget.fullUrl);
      _useAlbum = _albumUrl != null && _albumUrl != widget.fullUrl;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final memW = _memCacheExtent(constraints.maxWidth, dpr);
        final memH = _memCacheExtent(constraints.maxHeight, dpr);
        final url = _useAlbum ? _albumUrl! : widget.fullUrl;
        return CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          placeholderFadeInDuration: Duration.zero,
          memCacheWidth: memW,
          memCacheHeight: memH,
          httpHeaders: const {
            'User-Agent': 'Mesozoica/1.0 (mobile app; catalog album)',
          },
          imageBuilder: widget.imageBuilder,
          placeholder: (context, url) => widget.placeholder,
          errorWidget: (context, url, error) {
            if (_useAlbum) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _useAlbum) {
                  setState(() => _useAlbum = false);
                }
              });
              return widget.placeholder;
            }
            return widget.errorWidget;
          },
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
