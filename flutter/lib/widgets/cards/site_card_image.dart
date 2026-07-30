import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';
import '../../utils/curated_image_url.dart';

/// Card-front illustration: curated site-type image or bundled placeholder.
class SiteCardImage extends StatelessWidget {
  const SiteCardImage({
    super.key,
    required this.imageUrl,
  });

  final String? imageUrl;

  static const _fadeInDuration = Duration.zero;

  static bool isCuratedCardImageUrl(String? url) =>
      isCuratedSiteTypeImageUrl(url);

  @override
  Widget build(BuildContext context) {
    final curatedUrl = isCuratedCardImageUrl(imageUrl) ? imageUrl!.trim() : null;

    if (curatedUrl == null) {
      return const _FadingPlaceholderImage();
    }

    return CachedNetworkImage(
      imageUrl: curatedUrl,
      fit: BoxFit.cover,
      fadeInDuration: _fadeInDuration,
      fadeInCurve: Curves.easeIn,
      placeholderFadeInDuration: Duration.zero,
      httpHeaders: const {
        'User-Agent': 'Mesozoica/1.0 (mobile app; site catalog)',
      },
      placeholder: (context, url) => const SizedBox.shrink(),
      errorWidget: (context, url, error) => const _FadingPlaceholderImage(),
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
    duration: SiteCardImage._fadeInDuration,
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
        DinoCardTheme.sitePlaceholderAsset,
        fit: BoxFit.cover,
      ),
    );
  }
}
