import '../../../models/site.dart';
import '../../../models/user_notification.dart';
import 'celebration_descriptor.dart';

enum CelebrationKind { siteDiscovered, siteIdentified, siteDocumented }

class CelebrationEvent {
  const CelebrationEvent({
    required this.kind,
    required this.siteId,
    this.notificationId,
    this.site,
  });

  final CelebrationKind kind;
  final int siteId;
  final int? notificationId;
  final SiteSummary? site;

  String get notificationType => switch (kind) {
    CelebrationKind.siteDiscovered => 'site_discovered',
    CelebrationKind.siteIdentified => 'site_identified',
    CelebrationKind.siteDocumented => 'site_documented',
  };

  String get entityKey => 'site:$siteId';
  String get fallbackKey => '$notificationType:$entityKey';
  String get dedupeKey => notificationId != null && notificationId! > 0
      ? 'notification:$notificationId'
      : fallbackKey;

  factory CelebrationEvent.fromDescriptor(
    CelebrationDescriptor descriptor, {
    SiteSummary? site,
  }) {
    return CelebrationEvent(
      kind: kindForNotificationType(descriptor.type)!,
      siteId: descriptor.siteId,
      notificationId: descriptor.notificationId,
      site: site,
    );
  }

  factory CelebrationEvent.fromNotification(UserNotificationItem item) {
    return CelebrationEvent(
      kind: kindForNotificationType(item.type)!,
      siteId: item.siteId!,
      notificationId: item.id,
    );
  }

  static CelebrationKind? kindForNotificationType(String type) =>
      switch (type) {
        'site_discovered' => CelebrationKind.siteDiscovered,
        'site_identified' => CelebrationKind.siteIdentified,
        'site_documented' => CelebrationKind.siteDocumented,
        _ => null,
      };
}
