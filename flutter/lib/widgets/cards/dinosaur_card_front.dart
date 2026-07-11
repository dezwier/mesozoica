import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';

class DinosaurCardFront extends StatelessWidget {
  const DinosaurCardFront({super.key, required this.dinosaur});

  final DinosaurSummary dinosaur;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (dinosaur.mainImageUrl != null)
            CachedNetworkImage(
              imageUrl: dinosaur.mainImageUrl!,
              fit: BoxFit.cover,
              placeholder: (context, url) => const _ImagePlaceholder(),
              errorWidget: (context, url, error) => const _ImagePlaceholder(),
            )
          else
            const _ImagePlaceholder(),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.15),
                  Colors.black.withValues(alpha: 0.85),
                ],
                stops: const [0.45, 0.72, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dinosaur.name.toUpperCase(),
                  style: const TextStyle(
                    color: DinoCardTheme.titleWhite,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                if (dinosaur.shortDescription != null &&
                    dinosaur.shortDescription!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    dinosaur.shortDescription!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: DinoCardTheme.subtitleMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DinoCardTheme.backgroundElevated,
      alignment: Alignment.center,
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 56,
        color: DinoCardTheme.subtitleMuted.withValues(alpha: 0.6),
      ),
    );
  }
}
