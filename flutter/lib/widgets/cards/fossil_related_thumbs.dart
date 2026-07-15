import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../theme/dino_card_theme.dart';
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

  static const _gap = 14.0;

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
    final aspectRatio = DinoCardTheme.fossilThumbAspectRatio;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;

        var thumbHeight = maxHeight;
        var thumbWidth = thumbHeight * aspectRatio;
        final totalWidth = thumbCount * thumbWidth + (thumbCount - 1) * _gap;

        if (totalWidth > maxWidth) {
          thumbHeight = (maxWidth - (thumbCount - 1) * _gap) / (thumbCount * aspectRatio);
          thumbWidth = thumbHeight * aspectRatio;
        }

        final labelFontSize = (thumbWidth * 0.11).clamp(11.0, 14.0);

        return Align(
          alignment: Alignment.center,
          child: SizedBox(
            height: thumbHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasSite) ...[
                  SizedBox(
                    width: thumbWidth,
                    child: CardRecordThumb(
                      image: SiteCardImage(imageUrl: fossil.siteMainImageUrl),
                      label: _siteLabel,
                      labelFontSize: labelFontSize,
                      onTap: () => showSiteCardDialog(
                        context,
                        siteId: fossil.siteId!,
                      ),
                    ),
                  ),
                  const SizedBox(width: _gap),
                ],
                SizedBox(
                  width: thumbWidth,
                  child: CardRecordThumb(
                    image: DinosaurCardImage(
                      imageUrl: fossil.dinosaurMainImageUrl,
                    ),
                    label: fossil.dinosaurName,
                    labelFontSize: labelFontSize,
                    onTap: () => showDinosaurCardDialog(
                      context,
                      dinosaurId: fossil.dinosaurId,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
