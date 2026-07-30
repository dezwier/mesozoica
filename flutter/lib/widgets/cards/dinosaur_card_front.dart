import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import 'dinosaur_card_header.dart';
import 'dinosaur_card_image.dart';
import 'dinosaur_status_badge.dart';
import 'occurrence_id_badge.dart';
import 'tool_collect_badge.dart';

class DinosaurCardFront extends StatelessWidget {
  const DinosaurCardFront({
    super.key,
    required this.dinosaur,
    this.showFacts = true,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
    this.overlayHeightFactor = 0.52,
    this.showStatus = false,
    this.showCollectBadge = false,
    this.collectBusy = false,
    this.onCollect,
  });

  final DinosaurSummary dinosaur;
  final bool showFacts;
  final double titleFontSize;
  final double subtitleFontSize;
  final double overlayHeightFactor;
  final bool showStatus;
  final bool showCollectBadge;
  final bool collectBusy;
  final VoidCallback? onCollect;

  String get _description =>
      dinosaur.shortDescription != null &&
              dinosaur.shortDescription!.trim().isNotEmpty
          ? dinosaur.shortDescription!.trim()
          : '—';

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final status = dinosaur.status?.trim() ?? '';
    final showIdBadge = dinosaur.isInventoryOccurrence;

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DinosaurCardImage(imageUrl: dinosaur.mainImageUrl),
          Positioned.fill(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: overlayHeightFactor,
                widthFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: cardTheme.frontOverlayGradient(),
                  ),
                ),
              ),
            ),
          ),
          if (showIdBadge || showStatus || showCollectBadge)
            Positioned(
              top: 14,
              right: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showIdBadge)
                    OccurrenceIdBadge(
                      label: dinosaur.occurrenceIdBadgeLabel,
                    ),
                  if (showIdBadge && (showStatus || showCollectBadge))
                    const SizedBox(height: 6),
                  if (showCollectBadge)
                    ToolCollectBadge(
                      onPressed: onCollect,
                      busy: collectBusy,
                    ),
                  if (showStatus && status.isNotEmpty)
                    DinosaurStatusBadge(status: status),
                ],
              ),
            ),
          Positioned(
            left: 18,
            right: 18,
            bottom: math.max(16, titleFontSize * 0.45),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DinosaurCardHeader(
                  dinosaur: dinosaur,
                  titleFontSize: titleFontSize,
                  subtitleFontSize: subtitleFontSize,
                  centered: true,
                  overlayOnImage: true,
                ),
                if (showFacts) ...[
                  const SizedBox(height: 10),
                  Text(
                    _description,
                    textAlign: TextAlign.center,
                    style: cardTheme.frontOverlayBodyStyle(fontSize: 13),
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
