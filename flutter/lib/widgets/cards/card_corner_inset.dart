import 'package:flutter/material.dart';

/// Square thumbnail inset for card corners (site, dinosaur, etc.).
class CardCornerInset extends StatelessWidget {
  const CardCornerInset({
    super.key,
    required this.size,
    required this.onTap,
    required this.child,
  });

  final double size;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.85),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.42),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 16,
                  spreadRadius: 1,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.5),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
