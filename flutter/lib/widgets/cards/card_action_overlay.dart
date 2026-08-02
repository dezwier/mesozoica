import 'package:flutter/material.dart';

/// Centered round action button(s) shown after a long-press on an inventory card.
class CardActionOverlay extends StatelessWidget {
  const CardActionOverlay({
    super.key,
    required this.onDismiss,
    required this.onSettings,
  });

  final VoidCallback onDismiss;
  final Future<void> Function(BuildContext buttonContext) onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: Center(
          child: Tooltip(
            message: 'Settings',
            child: Semantics(
              button: true,
              label: 'Settings',
              child: Builder(
                builder: (buttonContext) {
                  return Material(
                    color: theme.colorScheme.surface.withValues(alpha: 0.94),
                    shape: const CircleBorder(),
                    elevation: 8,
                    shadowColor: Colors.black.withValues(alpha: 0.35),
                    child: InkWell(
                      onTap: () => onSettings(buttonContext),
                      customBorder: const CircleBorder(),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: Icon(
                          Icons.settings_rounded,
                          size: 24,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
