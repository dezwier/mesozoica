import 'package:flutter/material.dart';

import '../../theme/map_chrome_decorations.dart';
import '../../theme/map_chrome_theme.dart';

/// FAB tones for map controls.
enum ChromeFabTone {
  /// Dark recessed dial (default vintage style).
  glass,

  /// Warm leather fill for primary location-style actions.
  warm,

  /// Neutral gray for admin tools.
  grey,
}

/// Circular leather FAB with a simple brass border (matches Archive/Field toggle).
///
/// Layout is 48×48 (padded tap target) with a 40×40 visual.
class ChromeFab extends StatelessWidget {
  const ChromeFab({
    super.key,
    required this.onPressed,
    required this.child,
    this.tooltip,
    this.heroTag,
    this.tone = ChromeFabTone.glass,
    this.active = false,
  });

  static const double visualSize = 40;
  static const double layoutSize = 48;

  final VoidCallback? onPressed;
  final Widget child;
  final String? tooltip;
  final Object? heroTag;
  final ChromeFabTone tone;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final dial = _dialColor(tone: tone, enabled: enabled, active: active);

    Widget button = SizedBox(
      width: layoutSize,
      height: layoutSize,
      child: Center(
        child: DecoratedBox(
          decoration: MapChromeDecorations.brassCircle(dialFace: dial),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              splashColor: MapChromeTheme.brassLight.withValues(alpha: 0.25),
              highlightColor: MapChromeTheme.brassLight.withValues(alpha: 0.12),
              child: SizedBox(
                width: visualSize,
                height: visualSize,
                child: IconTheme.merge(
                  data: IconThemeData(
                    color: enabled
                        ? MapChromeTheme.cream
                        : MapChromeTheme.cream.withValues(alpha: 0.45),
                    size: 20,
                  ),
                  child: Center(child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (heroTag != null) {
      button = Hero(tag: heroTag!, child: button);
    }
    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }

  static Color _dialColor({
    required ChromeFabTone tone,
    required bool enabled,
    required bool active,
  }) {
    if (!enabled) {
      return MapChromeTheme.dialFaceDeep;
    }
    switch (tone) {
      case ChromeFabTone.glass:
        return active ? MapChromeTheme.dialFaceWarm : MapChromeTheme.dialFace;
      case ChromeFabTone.warm:
        return active ? MapChromeTheme.warmFab : MapChromeTheme.dialFaceWarm;
      case ChromeFabTone.grey:
        return active ? MapChromeTheme.dialFaceGrey : const Color(0xFF5A544C);
    }
  }
}
