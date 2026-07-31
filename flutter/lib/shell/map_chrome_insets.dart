import 'package:flutter/material.dart';

/// Spacing reserved for floating map chrome so map overlays clear it.
class MapChromeInsets {
  MapChromeInsets._();

  /// Height of the top control row (below the status bar).
  static const double topRowHeight = 48;

  /// Diameter of the mid chrome circle buttons (Sites / Dinosaurs).
  static const double bottomButtonSize = 64;

  /// Diameter of the outer chrome circle buttons (Profile / Tools).
  static const double bottomOuterButtonSize = 66;

  /// Diameter of the Fossils chrome circle button.
  static const double bottomFossilButtonSize = 62;

  /// Space under the circles for the label (gap + text).
  static const double bottomLabelBlockHeight = 20;

  /// Height of the bottom chrome row (above the home indicator).
  static const double bottomRowHeight =
      bottomOuterButtonSize + bottomLabelBlockHeight;

  /// Gap between FABs and the top of the bottom chrome row.
  static const double fabChromeGap = 24;

  static double top(BuildContext context) =>
      MediaQuery.paddingOf(context).top + topRowHeight;

  /// Full bottom chrome clearance (circles + labels + home indicator).
  static double bottom(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + bottomRowHeight;

  /// Places map FABs above the bottom chrome row.
  static double fabBottom(BuildContext context) =>
      bottom(context) + fabChromeGap;
}
