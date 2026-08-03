import 'package:flutter/material.dart';

/// Spacing reserved for floating map chrome so map overlays clear it.
class MapChromeInsets {
  MapChromeInsets._();

  /// Height of the top control row (below the status bar).
  static const double topRowHeight = 84;

  /// Compact weather control under notifications (+ gap).
  static const double weatherChipHeight = 44;

  /// Icon size in the bottom bar (bar height stays fixed).
  static const double bottomIconSize = 40;

  /// Space under icons for the label.
  static const double bottomLabelBlockHeight = 18;

  /// Height of the bottom chrome row (above the home indicator).
  static const double bottomRowHeight = 78;

  /// Gap between FABs and the top of the bottom chrome row.
  static const double fabChromeGap = 20;

  static double top(BuildContext context) =>
      MediaQuery.paddingOf(context).top + topRowHeight + weatherChipHeight;

  /// Full bottom chrome clearance (bar + home indicator).
  static double bottom(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + bottomRowHeight;

  /// Places map FABs above the bottom chrome row.
  static double fabBottom(BuildContext context) =>
      bottom(context) + fabChromeGap;
}
