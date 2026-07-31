import 'package:flutter/material.dart';

import '../../theme/map_chrome_theme.dart';

/// FAB tones for map controls.
enum ChromeFabTone {
  /// Dark glass (default mockup style).
  glass,

  /// Warm earth fill for primary location-style actions.
  warm,

  /// Neutral gray for admin tools.
  grey,
}

/// Circular dark-glass FAB matching the map chrome mockup.
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
    final fill = _fillColor(tone: tone, enabled: enabled, active: active);

    Widget button = SizedBox(
      width: layoutSize,
      height: layoutSize,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fill,
            border: Border.all(
              color: enabled
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.1),
              width: 0.75,
            ),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              splashColor: Colors.white24,
              highlightColor: Colors.white10,
              child: SizedBox(
                width: visualSize,
                height: visualSize,
                child: IconTheme.merge(
                  data: IconThemeData(
                    color: enabled
                        ? MapChromeTheme.cream
                        : MapChromeTheme.cream.withValues(alpha: 0.45),
                    size: 22,
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

  static Color _fillColor({
    required ChromeFabTone tone,
    required bool enabled,
    required bool active,
  }) {
    if (!enabled) {
      return const Color(0x66000000);
    }
    switch (tone) {
      case ChromeFabTone.glass:
        return active
            ? MapChromeTheme.darkGlass
            : MapChromeTheme.darkGlassSoft;
      case ChromeFabTone.warm:
        return active
            ? MapChromeTheme.warmFab.withValues(alpha: 0.95)
            : MapChromeTheme.warmFab.withValues(alpha: 0.85);
      case ChromeFabTone.grey:
        return active
            ? const Color(0xAA5A5A5A)
            : const Color(0x885A5A5A);
    }
  }
}
