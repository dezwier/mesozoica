import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import '../dino/dinosaur_article_drawer.dart';

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
              placeholder: (context, url) => _ImagePlaceholder(),
              errorWidget: (context, url, error) => _ImagePlaceholder(),
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
                    color: Colors.white,
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
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: Colors.black.withValues(alpha: 0.45),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                icon: const Icon(Icons.info_outline, size: 20),
                color: Colors.white,
                tooltip: 'Read article',
                visualDensity: VisualDensity.compact,
                onPressed: () => DinosaurArticleDrawer.show(
                  context,
                  dinosaur: dinosaur,
                ),
              ),
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
      color: DinoCardTheme.placeholderSurface(context),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 56,
        color: DinoCardTheme.labelColor(context).withValues(alpha: 0.6),
      ),
    );
  }
}
