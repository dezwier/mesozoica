import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';
import '../../theme/map_chrome_theme.dart';
import '../../utils/curated_image_url.dart';

/// Locked catalog tile art: heavily obscured black-and-white contour.
class CatalogSilhouetteImage extends StatelessWidget {
  const CatalogSilhouetteImage({
    super.key,
    required this.imageUrl,
    this.placeholderAsset = DinoCardTheme.frontPlaceholderAsset,
    this.isCuratedUrl = isCuratedDinosaurImageUrl,
  });

  final String? imageUrl;
  final String placeholderAsset;
  final bool Function(String? url) isCuratedUrl;

  /// Soft parchment ground behind the art.
  static const Color ground = MapChromeTheme.parchment;

  /// Near-black wash over the mono image so detail stays hard to read.
  static const Color obscureWash = Color(0x731A1510); // ~0.45

  /// True grayscale, moderately crushed (less midtone / color left).
  static const List<double> _obscureMono = <double>[
    0.128, 0.429, 0.043, 0, 0,
    0.128, 0.429, 0.043, 0, 0,
    0.128, 0.429, 0.043, 0, 0,
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    final curated = isCuratedUrl(imageUrl) ? imageUrl!.trim() : null;

    return ColoredBox(
      color: ground,
      child: curated == null
          ? _SilhouetteLayer(
              child: Image.asset(placeholderAsset, fit: BoxFit.cover),
            )
          : CachedNetworkImage(
              imageUrl: curated,
              fit: BoxFit.cover,
              fadeInDuration: Duration.zero,
              placeholderFadeInDuration: Duration.zero,
              httpHeaders: const {
                'User-Agent': 'Mesozoica/1.0 (mobile app; catalog album)',
              },
              imageBuilder: (context, provider) => _SilhouetteLayer(
                child: Image(image: provider, fit: BoxFit.cover),
              ),
              placeholder: (context, url) => const ColoredBox(color: ground),
              errorWidget: (context, url, error) => _SilhouetteLayer(
                child: Image.asset(placeholderAsset, fit: BoxFit.cover),
              ),
            ),
    );
  }
}

class _SilhouetteLayer extends StatelessWidget {
  const _SilhouetteLayer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColorFiltered(
          colorFilter: const ColorFilter.matrix(
            CatalogSilhouetteImage._obscureMono,
          ),
          child: child,
        ),
        const ColoredBox(color: CatalogSilhouetteImage.obscureWash),
      ],
    );
  }
}
