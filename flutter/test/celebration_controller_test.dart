import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesozoica/features/notifications/notifications.dart';

UserNotificationItem _notification(int id, String type, {bool read = false}) {
  return UserNotificationItem(
    id: id,
    type: type,
    siteId: id,
    siteLabel: 'Site $id',
    read: read,
    createdAt: DateTime.utc(2026, 8, 7, 10, id),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'first bind establishes a historical baseline without replaying',
    () async {
      final controller = CelebrationController();
      await controller.bindUser(7, [_notification(10, 'site_discovered')]);

      controller.reconcileUnread([_notification(10, 'site_discovered')]);
      expect(controller.current, isNull);

      controller.reconcileUnread([
        _notification(12, 'site_documented'),
        _notification(11, 'site_identified'),
      ]);
      expect(controller.current?.notificationId, 11);
      expect(controller.pendingCount, 2);
    },
  );

  test('deduplicates sources and completes callers in FIFO order', () async {
    SharedPreferences.setMockInitialValues({'celebration_presented_v1_7': 0});
    final controller = CelebrationController();
    await controller.bindUser(7, const []);

    final first = CelebrationEvent.fromNotification(
      _notification(1, 'site_discovered'),
    );
    final duplicate = CelebrationEvent.fromDescriptor(
      const CelebrationDescriptor(
        notificationId: 1,
        type: 'site_discovered',
        siteId: 1,
      ),
    );
    final second = CelebrationEvent.fromNotification(
      _notification(2, 'site_documented'),
    );

    var firstCompleted = false;
    controller.enqueue(first).then((_) => firstCompleted = true);
    controller.enqueue(duplicate);
    controller.enqueue(second);
    expect(controller.pendingCount, 2);
    expect(controller.current?.notificationId, 1);

    controller.dismissCurrent();
    await Future<void>.delayed(Duration.zero);
    expect(firstCompleted, isTrue);
    expect(controller.current?.notificationId, 2);
  });

  test('holds queued celebrations while backgrounded', () async {
    SharedPreferences.setMockInitialValues({'celebration_presented_v1_7': 0});
    final controller = CelebrationController();
    await controller.bindUser(7, const []);
    controller.setForeground(false);
    controller.reconcileUnread([_notification(3, 'site_identified')]);

    expect(controller.pendingCount, 1);
    expect(controller.current, isNull);

    controller.setForeground(true);
    expect(controller.current?.kind, CelebrationKind.siteIdentified);
  });
}
