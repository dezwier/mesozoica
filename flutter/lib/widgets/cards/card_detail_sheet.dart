import 'package:flutter/material.dart';

import '../../shell/shell_overlay_panel.dart';

/// Shared presentation for card detail overlays (map taps, cross-links).
///
/// Catalog screens embed turnable cards inline; this sheet is only for the
/// floating overlays that appear in front of the map / other tabs.
///
/// Layout matches [ShellOverlayPanel] catalog screens: card centered in the
/// band above the dismiss chrome. [openCount] lets [AppShell] freeze the map
/// and hide chrome while any card dialog is up.
class CardDetailSheet {
  CardDetailSheet._();

  /// Nested show/dismiss depth; AppShell listens to hide map chrome + freeze.
  static final ValueNotifier<int> openCount = ValueNotifier<int>(0);

  static bool get isOpen => openCount.value > 0;

  /// Top inset so floating XP-award badges clear celebration / marker cards.
  static const double topBreathingRoom = 68;

  /// Cap content like the catalog Cover Flow middle card (~72% of the band
  /// above the dismiss chrome), with headroom for celebration titles.
  static double maxContentHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final available = size.height -
        padding.top -
        topBreathingRoom -
        ShellOverlayPanel.bottomChromeHeight(context);
    return available * 0.85;
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
      child: Padding(
        // Center in the band above the dismiss row (same as inventory), with
        // top clearance for the global XP-award badge.
        padding: EdgeInsets.only(
          top: CardDetailSheet.topBreathingRoom,
          bottom: ShellOverlayPanel.bottomChromeHeight(context),
        ),
        child: _PullDownToDismiss(
          onDismiss: () => Navigator.of(context).maybePop(),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Vertical drag-down on a dialog card dismisses the sheet (mirrors inventory
/// first-card pull-to-close). Horizontal drags stay free for card flip.
class _PullDownToDismiss extends StatefulWidget {
  const _PullDownToDismiss({
    required this.onDismiss,
    required this.child,
  });

  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_PullDownToDismiss> createState() => _PullDownToDismissState();
}

class _PullDownToDismissState extends State<_PullDownToDismiss> {
  static const double _dismissThreshold = 88;
  static const double _flingVelocity = 400;

  double _drag = 0;

  void _onUpdate(DragUpdateDetails details) {
    final next = (_drag + details.delta.dy).clamp(0.0, 240.0);
    if (next != _drag) {
      setState(() => _drag = next);
    }
  }

  void _onEnd(DragEndDetails details) {
    final vy = details.velocity.pixelsPerSecond.dy;
    if (_drag >= _dismissThreshold ||
        (vy > _flingVelocity && _drag > 24)) {
      widget.onDismiss();
      return;
    }
    setState(() => _drag = 0);
  }

  void _onCancel() {
    if (_drag != 0) {
      setState(() => _drag = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: _onUpdate,
      onVerticalDragEnd: _onEnd,
      onVerticalDragCancel: _onCancel,
      child: Transform.translate(
        offset: Offset(0, _drag * 0.55),
        child: widget.child,
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
