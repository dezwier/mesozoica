class UserListEntry {
  final int id;
  final String username;
  final String displayName;
  final String? fullName;
  final String? imageUrl;
  final int level;

  const UserListEntry({
    required this.id,
    required this.username,
    required this.displayName,
    this.fullName,
    this.imageUrl,
    this.level = 1,
  });

  factory UserListEntry.fromJson(Map<String, dynamic> json) {
    return UserListEntry(
      id: json['id'] as int,
      username: json['username'] as String,
      displayName:
          json['display_name'] as String? ??
          json['displayName'] as String? ??
          json['username'] as String,
      fullName: json['full_name'] as String? ?? json['fullName'] as String?,
      imageUrl: json['image_url'] as String? ?? json['imageUrl'] as String?,
      level: json['level'] as int? ?? 1,
    );
  }

  factory UserListEntry.fromLeaderboardUser(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? json;
    return UserListEntry.fromJson(user);
  }
}
