import 'package:flutter/material.dart';

import '../../theme/map_chrome_decorations.dart';
import '../../theme/map_chrome_theme.dart';

/// Visual tone for [AppToast] badges.
enum AppToastTone {
  info,
  success,
  warning,
  error,
}

/// Floating leather badge toast — shared app-wide snackbar style.
abstract final class AppToast {
  static const Duration _defaultDuration = Duration(seconds: 3);

  static void show(
    BuildContext context,
    String message, {
    AppToastTone tone = AppToastTone.info,
    IconData? icon,
    Duration duration = _defaultDuration,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          duration: duration,
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          padding: EdgeInsets.zero,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          dismissDirection: DismissDirection.down,
          content: _AppToastBadge(
            message: trimmed,
            tone: tone,
            icon: icon ?? _defaultIcon(tone),
          ),
        ),
      );
  }

  static void info(BuildContext context, String message) =>
      show(context, message, tone: AppToastTone.info);

  static void success(BuildContext context, String message) =>
      show(context, message, tone: AppToastTone.success);

  static void warning(BuildContext context, String message) =>
      show(context, message, tone: AppToastTone.warning);

  static void error(BuildContext context, String message) =>
      show(context, message, tone: AppToastTone.error);

  static IconData _defaultIcon(AppToastTone tone) => switch (tone) {
        AppToastTone.info => Icons.info_outline_rounded,
        AppToastTone.success => Icons.check_circle_outline_rounded,
        AppToastTone.warning => Icons.warning_amber_rounded,
        AppToastTone.error => Icons.error_outline_rounded,
      };
}

class _AppToastBadge extends StatelessWidget {
  const _AppToastBadge({
    required this.message,
    required this.tone,
    required this.icon,
  });

  final String message;
  final AppToastTone tone;
  final IconData icon;

  Color get _accent => switch (tone) {
        AppToastTone.info => MapChromeTheme.brassLight,
        AppToastTone.success => const Color(0xFF8FBF8A),
        AppToastTone.warning => const Color(0xFFE0B35A),
        AppToastTone.error => const Color(0xFFE07060),
      };

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: DecoratedBox(
          decoration: MapChromeDecorations.leatherPanel(
            borderRadius: radius,
            soft: true,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _accent.withValues(alpha: 0.18),
                    border: Border.all(
                      color: _accent.withValues(alpha: 0.55),
                      width: 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(icon, size: 16, color: _accent),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    message,
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      fontFamily: MapChromeTheme.serifFont,
                      color: MapChromeTheme.cream,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      letterSpacing: 0.15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
