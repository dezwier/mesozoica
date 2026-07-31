import 'package:flutter/material.dart';

import '../../shell/shell_overlay_panel.dart';

/// Shared presentation for card detail overlays (map taps, cross-links).
///
/// Catalog screens embed turnable cards inline; this sheet is only for the
/// floating overlays that appear in front of the map / other tabs.
///
/// Layout matches [ShellOverlayPanel] catalog screens: card centered in the
/// viewport, dismiss control at bottom center. [openCount] lets [AppShell]
/// freeze the map and hide chrome while any card dialog is up.
class CardDetailSheet {
  CardDetailSheet._();

  /// Nested show/dismiss depth; AppShell listens to hide map chrome + freeze.
  static final ValueNotifier<int> openCount = ValueNotifier<int>(0);

  static bool get isOpen => openCount.value > 0;

  /// Cap content like the catalog Cover Flow middle card (~72% of SafeArea)
  /// plus a little headroom for celebration titles.
  static double maxContentHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    return (size.height - padding.top) * 0.85;
  }

  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) {
    final barrierLabel =
        MaterialLocalizations.of(context).modalBarrierDismissLabel;
    openCount.value += 1;
    return showGeneralDialog<T>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierLabel: barrierLabel,
      // Scrim is painted by [ShellOverlayPanel] (same as catalog screens).
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) {
        return CardDetailSheetShell(child: builder(context));
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: child,
        );
      },
    ).whenComplete(() {
      if (openCount.value > 0) {
        openCount.value -= 1;
      }
    });
  }
}

class CardDetailSheetShell extends StatelessWidget {
  const CardDetailSheetShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShellOverlayPanel(
      opaque: false,
      onClose: () => Navigator.of(context).maybePop(),
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: child,
        ),
      ),
    );
  }
}

/// Card body capped by [CardDetailSheet.maxContentHeight].
///
/// No inner scroll view — fixed-aspect turnable cards fit. Celebration titles
/// still fit on small phones.
class CardDetailSheetContent extends StatelessWidget {
  const CardDetailSheetContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: CardDetailSheet.maxContentHeight(context),
      ),
      child: child,
    );
  }
}
