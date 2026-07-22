import 'package:flutter/material.dart';

/// FAB tones aligned with map site-card action styling.
enum ChromeFabTone {
  /// Brown-ish neutral matching site Survey / Protect / Excavate buttons.
  warm,

  /// Neutral gray for admin tools.
  grey,
}

/// Small FAB chrome: M3 rounded-square shape + site-action fill/border.
///
/// Layout is 48×48 (padded tap target) with a 40×40 visual, matching
/// [FloatingActionButton.small] so stacked spacing stays the same.
class ChromeFab extends StatelessWidget {
  const ChromeFab({
    super.key,
    required this.onPressed,
    required this.child,
    this.tooltip,
    this.heroTag,
    this.tone = ChromeFabTone.warm,
    this.active = false,
  });

  /// M3 [FloatingActionButton.small] visual size.
  static const double visualSize = 40;

  /// M3 padded tap-target layout size (creates the usual FAB stack gaps).
  static const double layoutSize = 48;

  /// M3 small FAB corner radius (`RoundedRectangleBorder` 12).
  static const double cornerRadius = 12;

  final VoidCallback? onPressed;
  final Widget child;
  final String? tooltip;
  final Object? heroTag;
  final ChromeFabTone tone;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(cornerRadius);
    final colors = _gradientColors(
      tone: tone,
      enabled: enabled,
      active: active,
    );

    Widget button = SizedBox(
      width: layoutSize,
      height: layoutSize,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
            ),
            border: Border.all(
              color: enabled
                  ? const Color(0x40FFFFFF)
                  : const Color(0x22FFFFFF),
              width: 0.5,
            ),
            boxShadow: enabled
                ? const [
                    BoxShadow(
                      color: Color(0x44000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              borderRadius: radius,
              splashColor: Colors.white24,
              highlightColor: Colors.white10,
              child: SizedBox(
                width: visualSize,
                height: visualSize,
                child: IconTheme.merge(
                  data: IconThemeData(
                    color: enabled
                        ? const Color(0xFFF5F5F5)
                        : const Color(0x88BDBDBD),
                    size: 24,
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

  static List<Color> _gradientColors({
    required ChromeFabTone tone,
    required bool enabled,
    required bool active,
  }) {
    switch (tone) {
      case ChromeFabTone.warm:
        if (!enabled) {
          return const [Color(0xFF5C4E46), Color(0xFF4A3E38)];
        }
        // Browner than the site-action neutrals — closer to theme primary.
        return active
            ? const [Color(0xFF9A7B6E), Color(0xFF85685C)]
            : const [Color(0xFF8D6E63), Color(0xFF755A50)];
      case ChromeFabTone.grey:
        if (!enabled) {
          return const [Color(0xFF555555), Color(0xFF4A4A4A)];
        }
        return active
            ? const [Color(0xFF7A7A7A), Color(0xFF686868)]
            : const [Color(0xFF6E6E6E), Color(0xFF5C5C5C)];
    }
  }
}
