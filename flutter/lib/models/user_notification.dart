class UserNotificationItem {
  const UserNotificationItem({
    required this.id,
    required this.type,
    this.actorUserId,
    this.actorUsername = '',
    this.siteId,
    this.siteLabel = '',
    required this.read,
    required this.createdAt,
  });

  final int id;
  final String type;
  final int? actorUserId;
  final String actorUsername;
  final int? siteId;
  final String siteLabel;
  final bool read;
  final DateTime createdAt;

  bool get isFriendRequestReceived => type == 'friend_request_received';
  bool get isFriendRequestAccepted => type == 'friend_request_accepted';
  bool get isFriendRequestRelated =>
      isFriendRequestReceived || isFriendRequestAccepted;
  bool get isSiteDiscovered => type == 'site_discovered';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'actor_user_id': actorUserId,
      'actor_username': actorUsername,
      'site_id': siteId,
      'site_label': siteLabel,
      'read': read,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory UserNotificationItem.fromJson(Map<String, dynamic> json) {
    return UserNotificationItem(
      id: json['id'] as int,
      type: json['type'] as String,
      actorUserId: json['actor_user_id'] as int?,
      actorUsername: json['actor_username'] as String? ?? '',
      siteId: json['site_id'] as int?,
      siteLabel: json['site_label'] as String? ?? '',
      read: json['read'] as bool? ?? false,
      createdAt: _parseUtcThenLocal(json['created_at'] as String),
    );
  }

  UserNotificationItem copyWith({bool? read}) {
    return UserNotificationItem(
      id: id,
      type: type,
      actorUserId: actorUserId,
      actorUsername: actorUsername,
      siteId: siteId,
      siteLabel: siteLabel,
      read: read ?? this.read,
      createdAt: createdAt,
    );
  }

  static DateTime _parseUtcThenLocal(String value) {
    final hasTz =
        value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
    final parsed = hasTz ? DateTime.parse(value) : DateTime.parse('${value}Z');
    return parsed.toLocal();
  }
}
