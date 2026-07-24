import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Neutral gray gradient action button (map site card actions, tool card back).
class ChromeActionButton extends StatelessWidget {
  const ChromeActionButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  static const Color _label = Color(0xFFF5F5F5);
  static const Color _labelDisabled = Color(0x88BDBDBD);

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
          colors: enabled
              ? const [Color(0xFF5E5854), Color(0xFF4A4542)]
              : const [Color(0xFF464240), Color(0xFF3C3937)],
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
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: enabled ? _label : _labelDisabled,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
