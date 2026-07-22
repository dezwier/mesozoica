import 'package:flutter/material.dart';

/// Fullscreen panel that hosts Profile, Catalog, or Tools over the map.
///
/// Dismissal sits at bottom center over the content (no top chrome).
class ShellOverlayPanel extends StatelessWidget {
  const ShellOverlayPanel({
    super.key,
    required this.onClose,
    required this.child,
  });

  final VoidCallback onClose;
  final Widget child;

  static const double dismissSize = 64;
  static const double dismissBottomPadding = 12;

  /// Scroll padding so list content can clear the dismiss button.
  static double contentBottomInset(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom +
      dismissBottomPadding +
      dismissSize +
      24;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            bottom: false,
            child: child,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: dismissBottomPadding),
                child: Center(
                  child: Material(
                    elevation: 4,
                    shadowColor: Colors.black.withValues(alpha: 0.4),
                    shape: CircleBorder(
                      side: BorderSide(
                        color: scheme.outline.withValues(alpha: 0.45),
                        width: 2,
                      ),
                    ),
                    color: scheme.surface.withValues(alpha: 0.96),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onClose,
                      customBorder: const CircleBorder(),
                      child: SizedBox(
                        width: dismissSize,
                        height: dismissSize,
                        child: Icon(
                          Icons.close_rounded,
                          size: 32,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
