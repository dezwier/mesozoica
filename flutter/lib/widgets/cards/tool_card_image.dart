import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

class ToolCardImage extends StatelessWidget {
  const ToolCardImage({
    super.key,
    required this.imageUrl,
  });

  final String? imageUrl;

  static const _curatedMediaPath = '/media/tools/';
  static const _fadeInDuration = Duration.zero;

  static bool isCuratedCardImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) {
      return false;
    }
    return url.contains(_curatedMediaPath);
  }

  @override
  Widget build(BuildContext context) {
    final curatedUrl =
        isCuratedCardImageUrl(imageUrl) ? imageUrl!.trim() : null;

    if (curatedUrl == null) {
      return const _FadingPlaceholderImage();
    }

    return SizedBox.expand(
      child: CachedNetworkImage(
        imageUrl: curatedUrl,
        fit: BoxFit.cover,
        fadeInDuration: _fadeInDuration,
        fadeInCurve: Curves.easeIn,
        placeholderFadeInDuration: Duration.zero,
        httpHeaders: const {
          'User-Agent': 'Mesozoica/1.0 (mobile app; tool catalog)',
        },
        placeholder: (context, url) => const SizedBox.shrink(),
        errorWidget: (context, url, error) => const _FadingPlaceholderImage(),
      ),
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
    duration: ToolCardImage._fadeInDuration,
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
      child: SizedBox.expand(
        child: Image.asset(
          DinoCardTheme.sitePlaceholderAsset,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
