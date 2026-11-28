import 'package:flutter/material.dart';

import '../../models/catalog_data_source.dart';
import '../../models/fossil.dart';
import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/display_text.dart';
import 'card_record_thumb.dart';
import 'dinosaur_card_dialog.dart';
import 'dinosaur_card_image.dart';
import 'site_card_dialog.dart';
import 'site_card_image.dart';

/// Site and dinosaur thumbnails on the fossil card back — one scrollable row.
class FossilRelatedThumbs extends StatelessWidget {
  const FossilRelatedThumbs({super.key, required this.fossil});

  final FossilSummary fossil;

  static const _gap = 10.0;

  String get _siteLabel {
    final formation = fossil.geologicalFormation?.trim();
    if (formation != null && formation.isNotEmpty) {
      return toTitleCase(formation);
    }
    if (fossil.siteId != null) {
      return SiteSummary.formatSiteNumber(fossil.siteId!);
    }
    return 'Site';
  }

  CatalogDataSource get _siteDataSource {
    final siteId = fossil.siteId;
    if (siteId != null && siteId >= SiteSummary.fieldSiteIdBase) {
      return CatalogDataSource.field;
    }
    return fossil.isField ? CatalogDataSource.field : CatalogDataSource.archive;
  }

  @override
  Widget build(BuildContext context) {
    final hasSite = fossil.siteId != null;
    final aspectRatio = DinoCardTheme.fossilThumbAspectRatio;

    return LayoutBuilder(
      builder: (context, constraints) {
        final thumbHeight = constraints.maxHeight.isFinite &&
                constraints.maxHeight > 0
            ? constraints.maxHeight
            : 88.0;
        final thumbWidth = thumbHeight * aspectRatio;
        final labelFontSize = (thumbWidth * 0.11).clamp(10.0, 13.0);

        Widget thumb({
          required Widget image,
          required String label,
          required VoidCallback onTap,
        }) {
          return SizedBox(
            width: thumbWidth,
            height: thumbHeight,
            child: CardRecordThumb(
              image: image,
              label: label,
              labelFontSize: labelFontSize,
              onTap: onTap,
            ),
          );
        }

        return ListView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          children: [
            if (hasSite) ...[
              thumb(
                image: SiteCardImage(imageUrl: fossil.siteMainImageUrl),
                label: _siteLabel,
                onTap: () => showSiteCardDialog(
                  context,
                  siteId: fossil.siteId!,
                  dataSource: _siteDataSource,
                ),
              ),
              const SizedBox(width: _gap),
            ],
            thumb(
              image: DinosaurCardImage(imageUrl: fossil.dinosaurMainImageUrl),
              label: fossil.dinosaurName,
              onTap: () => showDinosaurCardDialog(
                context,
                dinosaurId: fossil.dinosaurId,
              ),
            ),
          ],
        );
      },
    );
  }
}
