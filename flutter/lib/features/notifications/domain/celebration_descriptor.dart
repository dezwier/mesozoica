class CelebrationDescriptor {
  const CelebrationDescriptor({
    required this.notificationId,
    required this.type,
    required this.siteId,
  });

  final int notificationId;
  final String type;
  final int siteId;

  factory CelebrationDescriptor.fromJson(Map<String, dynamic> json) {
    return CelebrationDescriptor(
      notificationId: json['notification_id'] as int? ?? 0,
      type: json['type'] as String? ?? '',
      siteId: json['site_id'] as int? ?? 0,
    );
  }
}
