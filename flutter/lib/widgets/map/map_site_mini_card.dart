import 'package:flutter/material.dart';

import '../../config/map_config.dart';
import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import '../cards/site_card_image.dart';
import '../cards/site_period_rock_type_lines.dart';

/// Circular rotate-mode site marker — styled like map chrome profile/catalog buttons.
class MapSiteMiniCard extends StatelessWidget {
  const MapSiteMiniCard({
    super.key,
    required this.site,
    this.selected = false,
    this.width = MapConfig.rotateMiniCardWidth,
  });

  final SiteSummary site;
  final bool selected;
  final double width;

  /// Circular markers use diameter for both dimensions.
  static double heightForWidth(double width) => width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cardTheme = DinoCardTheme.of(context);
    final size = width;
    final titleSize = (width * 0.13).clamp(5.0, 8.5);
    final inset = (width * 0.1).clamp(4.0, 8.0);
    final borderWidth = (width * 0.04).clamp(1.5, 2.5);

    return SizedBox(
      width: size,
      height: size,
      child: Material(
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        shape: CircleBorder(
          side: BorderSide(
            color: selected ? cardTheme.cardAccent : Colors.white,
            width: selected ? borderWidth + 0.5 : borderWidth,
          ),
        ),
        color: scheme.surface.withValues(alpha: 0.95),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SiteCardImage(imageUrl: site.mainImageUrl),
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                child: SitePeriodRockTypeLines(
                  site: site,
                  fontSize: titleSize,
                  mapMarker: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
