import '../models/user_notification.dart';
import 'api_client.dart';

class NotificationsResult {
  const NotificationsResult({required this.items});

  final List<UserNotificationItem> items;
}

class NotificationService {
  Future<NotificationsResult> getNotifications() async {
    try {
      final data =
          await ApiClient.instance.get('/api/v1/notifications');
      final list = data['notifications'] as List<dynamic>? ?? const [];
      final items = list
          .map((entry) =>
              UserNotificationItem.fromJson(entry as Map<String, dynamic>))
          .where((item) => item.isFriendRequestRelated)
          .toList();
      return NotificationsResult(items: items);
    } catch (_) {
      return const NotificationsResult(items: []);
    }
  }

  Future<bool> markRead(int notificationId) async {
    try {
      await ApiClient.instance.patch(
        '/api/v1/notifications/$notificationId/read',
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
