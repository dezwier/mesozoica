import 'package:flutter/material.dart';

/// Spacing reserved for floating map chrome so map overlays clear it.
class MapChromeInsets {
  MapChromeInsets._();

  /// Height of the top control row (below the status bar).
  static const double topRowHeight = 48;

  /// Diameter of the profile / catalog circle buttons.
  static const double bottomButtonSize = 56;

  /// Space under the circles for the label (gap + text).
  static const double bottomLabelBlockHeight = 20;

  /// Height of the bottom avatar/dino row (above the home indicator).
  static const double bottomRowHeight =
      bottomButtonSize + bottomLabelBlockHeight;

  static double top(BuildContext context) =>
      MediaQuery.paddingOf(context).top + topRowHeight;

  /// Full bottom chrome clearance (circles + labels + home indicator).
  static double bottom(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + bottomRowHeight;

  /// Aligns map / catalog FABs with the labels under the profile/catalog circles.
  static double fabBottom(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom;
}
