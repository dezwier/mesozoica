import 'package:flutter/material.dart';

import '../widgets/common/catalog_mode_toggle.dart';
import '../widgets/common/notification_icon_button.dart';
import '../models/user_notification.dart';
import 'map_chrome_insets.dart';
import 'map_user_hud.dart';
import 'map_weather_chip.dart';

/// Floating top controls: profile HUD, weather chip, Archive/Field toggle, notifications.
class MapTopChrome extends StatelessWidget {
  const MapTopChrome({
    super.key,
    required this.showNotifications,
    required this.onTapNotification,
    required this.onOpenProfile,
  });

  final bool showNotifications;
  final void Function(UserNotificationItem item) onTapNotification;
  final VoidCallback onOpenProfile;

  /// Extra fade below the control row so the scrim reaches further down.
  static const double _fadeExtension = 48;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final fadeHeight = topPad +
        MapChromeInsets.topRowHeight +
        MapChromeInsets.weatherChipHeight +
        _fadeExtension;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Stack(
        children: [
          IgnorePointer(
            child: SizedBox(
              height: fadeHeight,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.88),
                      Colors.black.withValues(alpha: 0.58),
                      Colors.black.withValues(alpha: 0.25),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.32, 0.68, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: MapChromeInsets.topRowHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: MapUserHud(onTap: onOpenProfile),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CatalogModeToggle(),
                            if (showNotifications) ...[
                              const SizedBox(width: 8),
                              NotificationIconButton(
                                onTapNotification: onTapNotification,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const MapWeatherChip(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
