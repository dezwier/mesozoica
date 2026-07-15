import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Square catalog thumbnail with a bottom name overlay for card-back lists.
class CardRecordThumb extends StatelessWidget {
  const CardRecordThumb({
    super.key,
    required this.image,
    required this.label,
    required this.onTap,
    this.labelFontSize = 7,
  });

  final Widget image;
  final String label;
  final VoidCallback onTap;
  final double labelFontSize;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.expand(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                image,
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.72),
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        4,
                        labelFontSize * 1.4,
                        4,
                        labelFontSize * 0.35,
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: cardTheme
                            .frontOverlaySubtitleStyle(fontSize: labelFontSize)
                            .copyWith(height: 1.1),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
