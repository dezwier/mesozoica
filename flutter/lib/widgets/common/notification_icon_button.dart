import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/notification_controller.dart';
import '../../models/user_notification.dart';

part 'notification_icon_button_list.dart';

const Color _iconColor = Colors.white;

/// Notification icon for the app bar with red badge count.
class NotificationIconButton extends StatelessWidget {
  static bool _notificationTapScheduled = false;

  const NotificationIconButton({
    super.key,
    required this.onTapNotification,
  });

  final void Function(UserNotificationItem item) onTapNotification;

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationController>(
      builder: (context, store, _) {
        final unread = store.unreadCountForBadge;
        return IconButton(
          visualDensity: VisualDensity.compact,
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(
              unread > 99 ? '99+' : '$unread',
              style: const TextStyle(fontSize: 10, color: Colors.white),
            ),
            backgroundColor: Colors.red,
            child: const Icon(Icons.notifications_outlined, color: _iconColor),
          ),
          onPressed: () => _showNotificationList(context, store),
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
