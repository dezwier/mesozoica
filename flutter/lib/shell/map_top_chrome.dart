import 'package:flutter/material.dart';

import '../widgets/common/catalog_mode_toggle.dart';
import '../widgets/common/notification_icon_button.dart';
import '../models/user_notification.dart';
import 'map_chrome_insets.dart';
import 'map_user_hud.dart';
import 'map_weather_chip.dart';

/// Top map scrim. Paint below tool HUDs so chips can slide over the fade.
class MapTopFade extends StatelessWidget {
  const MapTopFade({super.key});

  /// Extra fade below the control row so the scrim reaches further down.
  static const double fadeExtension = 48;

  static double height(BuildContext context) =>
      MediaQuery.paddingOf(context).top +
      MapChromeInsets.topRowHeight +
      MapChromeInsets.weatherChipHeight +
      fadeExtension;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: height(context),
      child: IgnorePointer(
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
    );
  }
}

/// Floating top controls: profile HUD, Archive/Field toggle, notifications, weather.
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

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const Align(
                alignment: Alignment.centerRight,
                child: MapWeatherChip(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
