import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../utils/display_text.dart';
import 'card_record_thumb.dart';
import 'dinosaur_card_dialog.dart';
import 'dinosaur_card_image.dart';
import 'site_card_dialog.dart';
import 'site_card_image.dart';

/// Site and dinosaur thumbnails on the fossil card back.
class FossilRelatedThumbs extends StatelessWidget {
  const FossilRelatedThumbs({
    super.key,
    required this.fossil,
  });

  final FossilSummary fossil;

  static const _gap = 6.0;
  static const _maxThumbSize = 80.0;

  String get _siteLabel {
    final formation = fossil.geologicalFormation?.trim();
    if (formation != null && formation.isNotEmpty) {
      return displayFactValue(formation);
    }
    if (fossil.siteId != null) {
      return 'Collection #${fossil.siteId}';
    }
    return 'Site';
  }

  @override
  Widget build(BuildContext context) {
    final hasSite = fossil.siteId != null;
    final thumbCount = hasSite ? 2 : 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final rawThumbSize = thumbCount == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - _gap) / 2;
        final thumbSize = math.min(rawThumbSize, _maxThumbSize);

        return SizedBox(
          height: thumbSize,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasSite) ...[
                SizedBox(
                  width: thumbSize,
                  height: thumbSize,
                  child: CardRecordThumb(
                    image: SiteCardImage(imageUrl: fossil.siteMainImageUrl),
                    label: _siteLabel,
                    onTap: () => showSiteCardDialog(
                      context,
                      siteId: fossil.siteId!,
                    ),
                  ),
                ),
                const SizedBox(width: _gap),
              ],
              SizedBox(
                width: thumbSize,
                height: thumbSize,
                child: CardRecordThumb(
                  image: DinosaurCardImage(
                    imageUrl: fossil.dinosaurMainImageUrl,
                  ),
                  label: fossil.dinosaurName,
                  onTap: () => showDinosaurCardDialog(
                    context,
                    dinosaurId: fossil.dinosaurId,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
