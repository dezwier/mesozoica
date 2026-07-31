import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../theme/dino_card_theme.dart';
import 'fossil_card_header.dart';
import 'fossil_card_image.dart';
import 'fossil_status_badge.dart';
import 'occurrence_id_badge.dart';

class FossilCardFront extends StatelessWidget {
  const FossilCardFront({
    super.key,
    required this.fossil,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
    this.overlayHeightFactor = 0.52,
    this.onStatusSelected,
  });

  final FossilSummary fossil;
  final double titleFontSize;
  final double subtitleFontSize;
  final double overlayHeightFactor;
  final ValueChanged<String>? onStatusSelected;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final status = fossil.status?.trim();
    final showIdBadge = fossil.isField;
    final showStatus = status != null && status.isNotEmpty;

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FossilCardImage(imageUrl: fossil.mainImageUrl),
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
          if (showIdBadge)
            Positioned(
              top: 14,
              left: 14,
              child: OccurrenceIdBadge(label: fossil.occurrenceIdBadgeLabel),
            ),
          if (showStatus)
            Positioned(
              top: 14,
              right: 14,
              child: FossilStatusBadge(
                status: status,
                onStatusSelected: onStatusSelected,
              ),
            ),
          Positioned(
            left: 18,
            right: 18,
            bottom: math.max(16, titleFontSize * 0.45),
            child: FossilCardHeader(
              fossil: fossil,
              titleFontSize: titleFontSize,
              subtitleFontSize: subtitleFontSize,
              centered: true,
              overlayOnImage: true,
              showOccurrenceSubtitle: true,
            ),
          ),
        ],
      ),
    );
  }
}
