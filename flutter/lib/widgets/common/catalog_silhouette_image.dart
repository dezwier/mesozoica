import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';
import '../../theme/map_chrome_theme.dart';
import '../../utils/curated_image_url.dart';
import 'catalog_album_network_image.dart';

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

  /// Soft parchment ground behind the art (light theme).
  static const Color groundLight = MapChromeTheme.parchment;

  /// Dark leather ground while images load (dark theme).
  static const Color groundDark = MapChromeTheme.leather;

  /// Soft parchment ground behind the art.
  static const Color ground = groundLight;

  /// Theme-aware tile / placeholder ground.
  static Color groundFor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? groundDark : groundLight;
  }

  /// Near-black wash over the mono image (dark theme).
  static const Color obscureWashDark = Color(0x731A1510); // ~0.45

  /// Light grey wash over the mono image (light theme).
  static const Color obscureWashLight = Color(0xB8D0CBC2); // ~0.72

  /// True grayscale, moderately crushed (less midtone / color left).
  static const List<double> _obscureMono = <double>[
    0.128, 0.429, 0.043, 0, 0,
    0.128, 0.429, 0.043, 0, 0,
    0.128, 0.429, 0.043, 0, 0,
    0, 0, 0, 1, 0,
  ];

  /// Theme-aware wash: dark brown in dark mode, light grey in light mode.
  static Color obscureWashFor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? obscureWashDark : obscureWashLight;
  }

  @override
  Widget build(BuildContext context) {
    final curated = isCuratedUrl(imageUrl) ? imageUrl!.trim() : null;
    final wash = obscureWashFor(context);
    final groundColor = groundFor(context);

    return ColoredBox(
      color: groundColor,
      child: curated == null
          ? _SilhouetteLayer(
              wash: wash,
              child: Image.asset(placeholderAsset, fit: BoxFit.cover),
            )
          : CatalogAlbumNetworkImage(
              fullUrl: curated,
              placeholder: ColoredBox(color: groundColor),
              errorWidget: _SilhouetteLayer(
                wash: wash,
                child: Image.asset(placeholderAsset, fit: BoxFit.cover),
              ),
              imageBuilder: (context, provider) => _SilhouetteLayer(
                wash: wash,
                child: Image(image: provider, fit: BoxFit.cover),
              ),
            ),
    );
  }
}

class _SilhouetteLayer extends StatelessWidget {
  const _SilhouetteLayer({
    required this.child,
    required this.wash,
  });

  final Widget child;
  final Color wash;

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
        ColoredBox(color: wash),
      ],
    );
  }
}
