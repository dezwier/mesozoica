import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/notification_controller.dart';
import '../../models/user_notification.dart';
import '../../theme/map_chrome_decorations.dart';
import '../../theme/map_chrome_theme.dart';

part 'notification_icon_button_list.dart';

/// Notification icon for map chrome — brass rim circle + gold unread dot.
class NotificationIconButton extends StatelessWidget {
  static bool _notificationTapScheduled = false;

  const NotificationIconButton({
    super.key,
    required this.onTapNotification,
  });

  final void Function(UserNotificationItem item) onTapNotification;

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationController>(
      builder: (context, store, _) {
        final unread = store.unreadCountForBadge;
        return GestureDetector(
          onTap: () => _showNotificationList(context, store),
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: _size,
            height: _size,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                DecoratedBox(
                  decoration: MapChromeDecorations.brassCircle(
                    dialFace: MapChromeTheme.dialFace,
                  ),
                  child: const SizedBox.expand(),
                ),
                const Icon(
                  Icons.notifications_outlined,
                  color: MapChromeTheme.cream,
                  size: 18,
                ),
                if (unread > 0)
                  Positioned(
                    top: 4,
                    right: 5,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: MapChromeTheme.goldBright,
                        border: Border.all(
                          color: MapChromeTheme.dialFaceDeep,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: MapChromeTheme.goldBright.withValues(
                              alpha: 0.55,
                            ),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showNotificationList(
    BuildContext context,
    NotificationController store,
  ) {
    final userId =
        Provider.of<AuthController>(context, listen: false).currentUser?.id;
    store.refreshInBackground(authenticatedUserId: userId);
    store.markCurrentAsSeenForBadge();
    if (!context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final position = box.localToGlobal(Offset.zero);
    final size = box.size;
    final media = MediaQuery.sizeOf(context);
    const padding = 8.0;
    const maxHeight = 400.0;
    final top = position.dy + size.height + 4;
    final left =
        (position.dx + size.width / 2 - 160.0).clamp(padding, media.width - 320 - padding);

    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    void remove() {
      entry.remove();
    }

    entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: remove,
          ),
          Positioned(
            left: left,
            top: top,
            width: 320,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        (media.height - top - padding).clamp(200.0, maxHeight),
                  ),
                  child: Consumer<NotificationController>(
                    builder: (context, store, _) => _NotificationListContent(
                      store: store,
                      onTapNotification: (item) async {
                        if (_notificationTapScheduled) return;
                        _notificationTapScheduled = true;
                        await store.markRead(item.id);
                        if (!context.mounted) return;
                        remove();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _notificationTapScheduled = false;
                          onTapNotification(item);
                        });
                      },
                      onMarkAllRead: store.markAllRead,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(entry);
  }
}
