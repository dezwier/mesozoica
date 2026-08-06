import 'package:flutter/material.dart';

import '../../theme/map_chrome_theme.dart';

/// Circular overlay action for inventory / dialog bottom chrome, with a small
/// caption under the dial.
class OverlayChromeButton extends StatelessWidget {
  const OverlayChromeButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.showBadge = false,
    this.heroTag,
    this.tooltip,
  });

  static const double buttonSize = 54;
  static const double _labelGap = 3;
  static const double _labelHeight = 14;

  /// Full vertical footprint (dial + caption) for layout math.
  static const double totalHeight = buttonSize + _labelGap + _labelHeight;

  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool showBadge;
  final Object? heroTag;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget dial = Material(
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.45),
      shape: CircleBorder(
        side: BorderSide(
          color: MapChromeTheme.brassRim.withValues(alpha: 0.55),
          width: 1.5,
        ),
      ),
      // Soft cream — warmer than plain white / theme surface.
      color: MapChromeTheme.cream.withValues(alpha: 0.94),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        splashColor: MapChromeTheme.parchment.withValues(alpha: 0.35),
        highlightColor: MapChromeTheme.parchment.withValues(alpha: 0.2),
        child: SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: Icon(icon, size: 28, color: MapChromeTheme.brownText),
        ),
      ),
    );

    if (showBadge) {
      dial = Stack(
        clipBehavior: Clip.none,
        children: [
          dial,
          Positioned(
            top: 1,
            right: 1,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: MapChromeTheme.goldBright,
                shape: BoxShape.circle,
                border: Border.all(
                  color: MapChromeTheme.cream.withValues(alpha: 0.85),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (heroTag != null) {
      dial = Hero(tag: heroTag!, child: dial);
    }
    if (tooltip != null) {
      dial = Tooltip(message: tooltip!, child: dial);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        dial,
        const SizedBox(height: _labelGap),
        SizedBox(
          width: buttonSize + 8,
          height: _labelHeight,
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MapChromeTheme.mutedGold,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFamily: MapChromeTheme.serifFont,
              letterSpacing: 0.45,
              height: 1.1,
              shadows: [Shadow(blurRadius: 5, color: Color(0xA6000000))],
            ),
          ),
        ),
      ],
    );
  }
}
