import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Card-front illustration: curated Railway image or bundled placeholder.
class DinosaurCardImage extends StatelessWidget {
  const DinosaurCardImage({
    super.key,
    required this.imageUrl,
  });

  final String? imageUrl;

  static const _curatedMediaPath = '/media/dinosaurs/';

  static bool isCuratedCardImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) {
      return false;
    }
    return url.contains(_curatedMediaPath);
  }

  @override
  Widget build(BuildContext context) {
    final curatedUrl = isCuratedCardImageUrl(imageUrl) ? imageUrl!.trim() : null;

    if (curatedUrl == null) {
      return Image.asset(
        DinoCardTheme.frontPlaceholderAsset,
        fit: BoxFit.cover,
      );
    }

    return CachedNetworkImage(
      imageUrl: curatedUrl,
      fit: BoxFit.cover,
      httpHeaders: const {
        'User-Agent': 'Mesozoica/1.0 (mobile app; dinosaur catalog)',
      },
      placeholder: (context, url) => Image.asset(
        DinoCardTheme.frontPlaceholderAsset,
        fit: BoxFit.cover,
      ),
      errorWidget: (context, url, error) => Image.asset(
        DinoCardTheme.frontPlaceholderAsset,
        fit: BoxFit.cover,
      ),
    );
  }
}
