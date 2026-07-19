import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/controllers/notification_controller.dart';
import 'package:mesozoica/models/user_notification.dart';
import 'package:mesozoica/services/notification_service.dart';

UserNotificationItem _item({
  required int id,
  bool read = false,
  String type = 'site_discovered',
}) {
  return UserNotificationItem(
    id: id,
    type: type,
    siteId: 1,
    siteLabel: 'Site $id',
    read: read,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

class _SeededNotificationService extends NotificationService {
  _SeededNotificationService({required this.items});

  final List<UserNotificationItem> items;
  final List<int> markedIds = [];

  @override
  Future<NotificationsResult> getNotifications() async {
    return NotificationsResult(items: List.of(items));
  }

  @override
  Future<bool> markRead(int notificationId) async {
    markedIds.add(notificationId);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('markRead clears OS badge when last unread is read', () async {
    final badgeCounts = <int>[];
    final service = _SeededNotificationService(
      items: [_item(id: 10), _item(id: 11, read: true)],
    );
    final controller = NotificationController(
      notificationService: service,
      setAppBadgeCount: (count) async => badgeCounts.add(count),
    );

    await controller.refreshAndWait(authenticatedUserId: 42);
    expect(controller.unreadCount, 1);
    expect(badgeCounts.last, 1);

    await controller.markRead(10);
    expect(controller.unreadCount, 0);
    expect(badgeCounts.last, 0);
    expect(service.markedIds, [10]);
  });

  test('markAllRead syncs badge to zero', () async {
    final badgeCounts = <int>[];
    final service = _SeededNotificationService(
      items: [_item(id: 1), _item(id: 2)],
    );
    final controller = NotificationController(
      notificationService: service,
      setAppBadgeCount: (count) async => badgeCounts.add(count),
    );

    await controller.refreshAndWait(authenticatedUserId: 7);
    expect(controller.unreadCount, 2);

    await controller.markAllRead();
    expect(controller.unreadCount, 0);
    expect(badgeCounts.last, 0);
  });

  test('clear resets app badge to zero', () async {
    final badgeCounts = <int>[];
    final service = _SeededNotificationService(items: [_item(id: 3)]);
    final controller = NotificationController(
      notificationService: service,
      setAppBadgeCount: (count) async => badgeCounts.add(count),
    );

    await controller.refreshAndWait(authenticatedUserId: 9);
    expect(badgeCounts.last, 1);

    controller.clear();
    expect(controller.unreadCount, 0);
    expect(badgeCounts.last, 0);
  });
}
