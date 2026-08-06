import 'package:mesozoica/models/user_notification.dart';
import 'package:mesozoica/core/networking/api_client.dart';
import 'package:mesozoica/core/networking/api_transport.dart';

class NotificationsResult {
  const NotificationsResult({required this.items});

  final List<UserNotificationItem> items;
}

class NotificationService {
  NotificationService({ApiTransport? transport})
    : _transport = transport ?? ApiClient.instance;

  final ApiTransport _transport;

  Future<NotificationsResult> getNotifications() async {
    try {
      final data = await _transport.get('/api/v1/notifications');
      final list = data['notifications'] as List<dynamic>? ?? const [];
      final items = list
          .map(
            (entry) =>
                UserNotificationItem.fromJson(entry as Map<String, dynamic>),
          )
          .where((item) => item.isInAppBellItem)
          .toList();
      return NotificationsResult(items: items);
    } catch (_) {
      return const NotificationsResult(items: []);
    }
  }

  Future<bool> markRead(int notificationId) async {
    try {
      await _transport.patch('/api/v1/notifications/$notificationId/read');
      return true;
    } catch (_) {
      return false;
    }
  }
}
