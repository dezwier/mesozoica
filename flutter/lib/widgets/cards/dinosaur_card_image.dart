import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';
import '../../utils/curated_image_url.dart';
import '../../utils/network_image_mem_cache.dart';

/// Card-front illustration: curated Railway image or bundled placeholder.
class DinosaurCardImage extends StatelessWidget {
  const DinosaurCardImage({super.key, required this.imageUrl});

  final String? imageUrl;

  static const _fadeInDuration = Duration.zero;

  static bool isCuratedCardImageUrl(String? url) =>
      isCuratedDinosaurImageUrl(url);

  @override
  Widget build(BuildContext context) {
    final curatedUrl = isCuratedCardImageUrl(imageUrl)
        ? imageUrl!.trim()
        : null;

    if (curatedUrl == null) {
      return const _FadingPlaceholderImage();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        return CachedNetworkImage(
          imageUrl: curatedUrl,
          fit: BoxFit.cover,
          fadeInDuration: _fadeInDuration,
          fadeInCurve: Curves.easeIn,
          placeholderFadeInDuration: Duration.zero,
          memCacheWidth: networkImageMemCacheExtent(constraints.maxWidth, dpr),
          memCacheHeight: networkImageMemCacheExtent(
            constraints.maxHeight,
            dpr,
          ),
          httpHeaders: const {
            'User-Agent': 'Mesozoica/1.0 (mobile app; dinosaur catalog)',
          },
          placeholder: (context, url) => const SizedBox.shrink(),
          errorWidget: (context, url, error) => const _FadingPlaceholderImage(),
        );
      },
    );
  }
}

class _FadingPlaceholderImage extends StatefulWidget {
  const _FadingPlaceholderImage();

  @override
  State<_FadingPlaceholderImage> createState() =>
      _FadingPlaceholderImageState();
}

class _FadingPlaceholderImageState extends State<_FadingPlaceholderImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DinosaurCardImage._fadeInDuration,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeIn),
      child: Image.asset(
        DinoCardTheme.frontPlaceholderAsset,
        fit: BoxFit.cover,
      ),
    );
  }
}
