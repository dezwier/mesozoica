import 'package:flutter/material.dart';

import '../widgets/common/catalog_mode_toggle.dart';
import '../widgets/common/notification_icon_button.dart';
import '../models/user_notification.dart';
import 'map_chrome_insets.dart';
import 'map_user_hud.dart';

/// Floating top controls: profile HUD, Archive/Field toggle, notifications.
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.62),
              Colors.black.withValues(alpha: 0.28),
              Colors.black.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: MapChromeInsets.topRowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
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
          ),
        ),
      ),
    );
  }
}
