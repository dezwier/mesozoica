import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/controllers/notification_controller.dart';
import 'package:mesozoica/models/user_notification.dart';
import 'package:mesozoica/services/api_response_cache.dart';
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

class _MemoryResponseCache implements ResponseCache {
  final Map<String, Object> _values = {};

  String _key(String name, int? userId) => '$name:${userId ?? 0}';

  @override
  Future<void> clearForUser(int? userId) async {
    final suffix = ':${userId ?? 0}';
    _values.removeWhere((key, _) => key.endsWith(suffix));
  }

  @override
  Future<String?> get(
    String name,
    int? userId, {
    Duration ttl = const Duration(hours: 24),
  }) async {
    return _values[_key(name, userId)] as String?;
  }

  @override
  Future<void> set(String name, int? userId, Object payload) async {
    _values[_key(name, userId)] = payload is String
        ? payload
        : jsonEncode(payload);
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
      responseCache: _MemoryResponseCache(),
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
      responseCache: _MemoryResponseCache(),
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
      responseCache: _MemoryResponseCache(),
      setAppBadgeCount: (count) async => badgeCounts.add(count),
    );

    await controller.refreshAndWait(authenticatedUserId: 9);
    expect(badgeCounts.last, 1);

    controller.clear();
    expect(controller.unreadCount, 0);
    expect(badgeCounts.last, 0);
  });
}
