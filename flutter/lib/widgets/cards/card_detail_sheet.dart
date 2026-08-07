import 'package:flutter/material.dart';

import '../../shell/shell_overlay_panel.dart';

/// Shared presentation for card detail overlays (map taps, cross-links).
///
/// Catalog screens embed turnable cards inline; this sheet is only for the
/// floating overlays that appear in front of the map / other tabs.
///
/// Layout matches [ShellOverlayPanel] catalog screens: card centered in the
/// band above the dismiss chrome. [openCount] lets [AppShell] freeze map chrome
/// / Mapbox while any card dialog is up (GPS stays map-grade via
/// [MapScreen.highPrecisionGps]).
class CardDetailSheet {
  CardDetailSheet._();

  /// Nested show/dismiss depth; AppShell listens to hide map chrome + freeze.
  static final ValueNotifier<int> openCount = ValueNotifier<int>(0);
  static final Map<CardDetailIdentity, Route<dynamic>> _routes = {};

  static bool get isOpen => openCount.value > 0;

  /// Top inset so floating XP-award badges clear marker / tool cards.
  /// Celebrations omit this — XP lives in the plaque, so content is centered
  /// between the dismiss chrome and the top of the safe area.
  static const double topBreathingRoom = 68;

  /// Cap content like the catalog Cover Flow middle card (~72% of the band
  /// above the dismiss chrome), with headroom for celebration titles.
  static double maxContentHeight(
    BuildContext context, {
    bool clearTopForXpBadges = true,
  }) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final topClearance = clearTopForXpBadges ? topBreathingRoom : 0.0;
    final available =
        size.height -
        padding.top -
        topClearance -
        ShellOverlayPanel.bottomChromeHeight(context);
    return available * 0.85;
  }

  /// Show a card overlay.
  ///
  /// Set [clearTopForXpBadges] false for celebrations so the full stack
  /// (plaque + card) is vertically centered between dismiss and top of screen.
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool clearTopForXpBadges = true,
    CardDetailIdentity? identity,
  }) {
    final barrierLabel = MaterialLocalizations.of(
      context,
    ).modalBarrierDismissLabel;
    openCount.value += 1;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = RawDialogRoute<T>(
      pageBuilder: (context, animation, secondaryAnimation) {
        return CardDetailSheetShell(
          clearTopForXpBadges: clearTopForXpBadges,
          child: builder(context),
        );
      },
      barrierDismissible: false,
      barrierLabel: barrierLabel,
      // Scrim is painted by [ShellOverlayPanel] (same as catalog screens).
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(opacity: curved, child: child);
      },
    );
    if (identity != null) _routes[identity] = route;
    return navigator.push<T>(route).whenComplete(() {
      if (identity != null && identical(_routes[identity], route)) {
        _routes.remove(identity);
      }
      if (openCount.value > 0) {
        openCount.value -= 1;
      }
    });
  }

  static void dismissMatching(CardDetailIdentity identity) {
    final route = _routes.remove(identity);
    final navigator = route?.navigator;
    if (route != null && navigator != null && route.isActive) {
      navigator.removeRoute(route);
    }
  }
}

class CardDetailIdentity {
  const CardDetailIdentity(this.entityType, this.entityId);
  const CardDetailIdentity.site(int siteId) : this('site', siteId);

  final String entityType;
  final int entityId;

  @override
  bool operator ==(Object other) =>
      other is CardDetailIdentity &&
      other.entityType == entityType &&
      other.entityId == entityId;

  @override
  int get hashCode => Object.hash(entityType, entityId);
}

class CardDetailSheetShell extends StatelessWidget {
  const CardDetailSheetShell({
    super.key,
    required this.child,
    this.clearTopForXpBadges = true,
    this.onClose,
  });

  final Widget child;

  /// When true, reserves [CardDetailSheet.topBreathingRoom] under the status
  /// bar for floating XP badges. Celebrations leave this false.
  final bool clearTopForXpBadges;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final topPad = clearTopForXpBadges ? CardDetailSheet.topBreathingRoom : 0.0;
    return ShellOverlayPanel(
      opaque: false,
      onClose: onClose ?? () => Navigator.of(context).maybePop(),
      child: Padding(
        // Center in the band above the dismiss row. Marker cards keep top
        // clearance for floating XP badges; celebrations use the full band.
        padding: EdgeInsets.only(
          top: topPad,
          bottom: ShellOverlayPanel.bottomChromeHeight(context),
        ),
        child: _PullDownToDismiss(
          onDismiss: onClose ?? () => Navigator.of(context).maybePop(),
          child: Center(
            child: Material(color: Colors.transparent, child: child),
          ),
        ),
      ),
    );
  }
}

/// Vertical drag-down on a dialog card dismisses the sheet (mirrors inventory
/// first-card pull-to-close). Horizontal drags stay free for card flip.
class _PullDownToDismiss extends StatefulWidget {
  const _PullDownToDismiss({required this.onDismiss, required this.child});

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
    if (_drag >= _dismissThreshold || (vy > _flingVelocity && _drag > 24)) {
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
  const CardDetailSheetContent({
    super.key,
    required this.child,
    this.clearTopForXpBadges = true,
  });

  final Widget child;

  /// Match [CardDetailSheet.show] / shell so height math uses the same band.
  final bool clearTopForXpBadges;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: CardDetailSheet.maxContentHeight(
          context,
          clearTopForXpBadges: clearTopForXpBadges,
        ),
      ),
      child: child,
    );
  }
}
