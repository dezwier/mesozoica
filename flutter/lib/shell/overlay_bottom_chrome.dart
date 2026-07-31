import 'package:flutter/material.dart';

/// Bottom action strip for overlay panels — taller readability fade than the
/// map bar, sized for [OverlayChromeButton].
class OverlayBottomChrome extends StatelessWidget {
  const OverlayBottomChrome({super.key, required this.child});

  final Widget child;

  /// Button row height above the home indicator.
  static const double rowHeight = 88;

  /// Extra fade height above the button row.
  static const double fadeExtra = 82;

  /// Full clearance: home indicator + button row.
  static double height(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + rowHeight;

  /// Gradient band height (fade + row + home indicator).
  static double fadeHeight(BuildContext context) =>
      height(context) + fadeExtra;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: fadeHeight(context),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.78),
                      Colors.black.withValues(alpha: 0.42),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.42, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomInset + 2,
            child: SizedBox(
              height: rowHeight - 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(child: child),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
