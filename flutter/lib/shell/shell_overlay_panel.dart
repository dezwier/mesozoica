import 'package:flutter/material.dart';

import '../widgets/common/overlay_chrome_button.dart';
import 'overlay_bottom_chrome.dart';
import 'shell_overlay_scope.dart';

export 'shell_overlay_scope.dart';

/// Fullscreen panel that hosts Profile, Sites, Fossils, Dinosaurs, or Tools
/// over the map.
///
/// Dismissal sits in the bottom chrome row (optionally after leading actions).
///
/// When [opaque] is false, the map stays visible under a dim scrim (catalog /
/// Tools). Profile keeps the opaque scaffold fill.
class ShellOverlayPanel extends StatelessWidget {
  const ShellOverlayPanel({
    super.key,
    required this.onClose,
    required this.child,
    this.opaque = true,
    this.showDismiss = true,
  });

  final VoidCallback onClose;
  final Widget child;

  /// When true, fills with [ThemeData.scaffoldBackgroundColor]. When false,
  /// uses a translucent black scrim so the map shows through.
  final bool opaque;

  /// When false, the child owns the bottom dismiss control (catalog screens).
  final bool showDismiss;

  /// Height of the bottom action row (home indicator + buttons).
  static double bottomChromeHeight(BuildContext context) =>
      OverlayBottomChrome.height(context);

  /// Scroll padding so list content can clear the bottom chrome row.
  static double contentBottomInset(BuildContext context) =>
      bottomChromeHeight(context) + 24;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ShellOverlayScope(
      onClose: onClose,
      opaque: opaque,
      child: Material(
        color: opaque ? theme.scaffoldBackgroundColor : Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!opaque)
              const Positioned.fill(
                child: ColoredBox(color: Color(0x8A000000)), // ~black54
              ),
            SafeArea(
              bottom: false,
              child: child,
            ),
            if (showDismiss)
              OverlayBottomChrome(
                child: OverlayChromeButton(
                  onPressed: onClose,
                  icon: Icons.close_rounded,
                  label: 'Close',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
