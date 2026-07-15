import 'package:flutter/material.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.elevation,
    this.margin,
    this.padding,
    this.borderRadius,
    this.color,
    this.decoration,
    this.onTap,
  });

  const AppCard.profile({
    super.key,
    required this.child,
    this.elevation = 1,
    this.margin,
    this.padding,
    this.borderRadius = 5,
    this.color,
    this.decoration,
    this.onTap,
  });

  final Widget child;
  final double? elevation;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final Color? color;
  final Decoration? decoration;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      elevation: elevation ?? 1,
      margin: margin,
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius ?? 5),
      ),
      child: decoration == null
          ? child
          : DecoratedBox(decoration: decoration!, child: child),
    );
    if (padding != null) {
      return Padding(padding: padding!, child: card);
    }
    if (onTap != null) {
      return InkWell(onTap: onTap, child: card);
    }
    return card;
  }
}
