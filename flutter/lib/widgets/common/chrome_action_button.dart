import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Neutral gray gradient action button (map site card actions, tool card back,
/// catalog category toggles).
class ChromeActionButton extends StatelessWidget {
  const ChromeActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Stronger pressed look for toggle/selection (e.g. catalog categories).
  final bool selected;

  static const Color _label = Color(0xFFF5F5F5);
  static const Color _labelDisabled = Color(0x88BDBDBD);

  static List<Color> _gradientColors({
    required bool enabled,
    required bool selected,
  }) {
    if (!enabled) {
      return const [Color(0xFF464240), Color(0xFF3C3937)];
    }
    if (selected) {
      // Warm raised fill — clearly distinct from the default gray.
      return const [Color(0xFF9A7B6E), Color(0xFF85685C)];
    }
    return const [Color(0xFF5E5854), Color(0xFF4A4542)];
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(DinoCardTheme.borderRadius);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _gradientColors(enabled: enabled, selected: selected),
        ),
        border: Border.all(
          color: !enabled
              ? const Color(0x22FFFFFF)
              : selected
                  ? const Color(0xCCFFFFFF)
                  : const Color(0x40FFFFFF),
          width: selected && enabled ? 2 : 0.5,
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: selected
                      ? const Color(0x66000000)
                      : const Color(0x44000000),
                  blurRadius: selected ? 12 : 8,
                  offset: const Offset(0, 2),
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
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: enabled ? _label : _labelDisabled,
                fontSize: 14,
                fontWeight:
                    selected && enabled ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
