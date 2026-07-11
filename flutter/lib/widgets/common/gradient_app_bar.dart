import 'package:flutter/material.dart';

/// Glossy diagonal gradient top bar (Archipelago-style), tuned for Mesozoica browns.
class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GradientAppBar({
    super.key,
    required this.title,
    this.actions,
  });

  final Widget title;
  final List<Widget>? actions;

  static const Color _foregroundColor = Colors.white;
  static const double _height = 46;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const [0.0, 0.5, 1.0],
      colors: isDark
          ? [
              const Color.fromARGB(255, 76, 69, 65),
              const Color.fromARGB(255, 62, 50, 45),
              const Color(0xFF4A3F38),
            ]
          : [
              const Color.fromARGB(255, 213, 210, 206),
              const Color.fromARGB(255, 216, 213, 211),
              const Color.fromARGB(255, 207, 199, 196),
            ],
    );

    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 2,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: AppBar(
        toolbarHeight: _height,
        title: title,
        titleSpacing: 8,
        centerTitle: false,
        actions: actions,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: _foregroundColor,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
