import 'package:flutter/material.dart';

import '../widgets/common/catalog_mode_toggle.dart';
import '../widgets/common/notification_icon_button.dart';
import '../models/user_notification.dart';
import 'map_chrome_insets.dart';

/// Floating top controls over the map: logo, Archive/Field toggle, notifications.
class MapTopChrome extends StatelessWidget {
  const MapTopChrome({
    super.key,
    required this.showNotifications,
    required this.onTapNotification,
  });

  final bool showNotifications;
  final void Function(UserNotificationItem item) onTapNotification;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.45),
              Colors.black.withValues(alpha: 0.0),
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: MapChromeInsets.topRowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Image.asset(
                        'assets/images/logo.png',
                        height: 32,
                      ),
                    ),
                  ),
                  const CatalogModeToggle(),
                  if (showNotifications)
                    Align(
                      alignment: Alignment.centerRight,
                      child: NotificationIconButton(
                        onTapNotification: onTapNotification,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
