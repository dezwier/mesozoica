import 'package:flutter/material.dart';

/// Glossy diagonal gradient top bar (Archipelago-style), tuned for Mesozoica browns.
class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GradientAppBar({
    super.key,
    required this.title,
    this.center,
    this.actions,
  });

  final Widget title;
  final Widget? center;
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
              const Color.fromARGB(255, 195, 190, 186),
              const Color.fromARGB(255, 198, 193, 189),
              const Color.fromARGB(255, 188, 180, 177),
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
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: SizedBox(
          width: double.infinity,
          height: _height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: title,
              ),
              if (center != null) center!,
              if (actions != null && actions!.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: actions!,
                  ),
                ),
            ],
          ),
        ),
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: _foregroundColor,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
