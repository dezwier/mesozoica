class Profile {
  final int id;
  final String displayName;
  final String? username;
  final int xp;
  final String specialization;
  final int yearsOfExperience;
  final String notableDiscovery;
  final String favoriteEra;
  final int level;
  final List<String> achievements;
  final String profileImage;
  final String bio;
  final String currentLocation;
  final int actualDinosaursCount;
  final int actualFossilsCount;
  final int actualSitesCount;
  final String email;
  final String? fullName;

  const Profile({
    required this.id,
    required this.displayName,
    this.username,
    required this.xp,
    required this.specialization,
    required this.yearsOfExperience,
    required this.notableDiscovery,
    required this.favoriteEra,
    required this.level,
    required this.achievements,
    required this.profileImage,
    required this.bio,
    required this.currentLocation,
    required this.actualDinosaursCount,
    required this.actualFossilsCount,
    required this.actualSitesCount,
    required this.email,
    this.fullName,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as int? ?? 0,
      displayName: json['display_name'] as String? ??
          json['displayName'] as String? ??
          'Unknown User',
      username: json['username'] as String?,
      xp: json['xp'] as int? ?? 0,
      specialization:
          json['specialization'] as String? ?? 'Paleontologist',
      yearsOfExperience: json['years_of_experience'] as int? ??
          json['yearsOfExperience'] as int? ??
          0,
      notableDiscovery: json['notable_discovery'] as String? ??
          json['notableDiscovery'] as String? ??
          '',
      favoriteEra:
          json['favorite_era'] as String? ?? json['favoriteEra'] as String? ?? '',
      level: json['level'] as int? ?? 1,
      achievements: (json['achievements'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .toList() ??
          const [],
      profileImage: json['profile_image_url'] as String? ??
          json['image_url'] as String? ??
          json['profileImage'] as String? ??
          '',
      bio: json['bio'] as String? ?? '',
      currentLocation: json['current_location'] as String? ??
          json['currentLocation'] as String? ??
          '',
      actualDinosaursCount: json['actual_dinosaurs_count'] as int? ?? 0,
      actualFossilsCount: json['actual_fossils_count'] as int? ?? 0,
      actualSitesCount: json['actual_sites_count'] as int? ?? 0,
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String? ?? json['fullName'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'username': username,
        'xp': xp,
        'specialization': specialization,
        'yearsOfExperience': yearsOfExperience,
        'notableDiscovery': notableDiscovery,
        'favoriteEra': favoriteEra,
        'level': level,
        'achievements': achievements,
        'profileImage': profileImage,
        'bio': bio,
        'currentLocation': currentLocation,
        'actualDinosaursCount': actualDinosaursCount,
        'actualFossilsCount': actualFossilsCount,
        'actualSitesCount': actualSitesCount,
        'email': email,
        'fullName': fullName,
      };

  Profile copyWith({
    String? displayName,
    String? username,
    String? profileImage,
    String? fullName,
  }) {
    return Profile(
      id: id,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      xp: xp,
      specialization: specialization,
      yearsOfExperience: yearsOfExperience,
      notableDiscovery: notableDiscovery,
      favoriteEra: favoriteEra,
      level: level,
      achievements: achievements,
      profileImage: profileImage ?? this.profileImage,
      bio: bio,
      currentLocation: currentLocation,
      actualDinosaursCount: actualDinosaursCount,
      actualFossilsCount: actualFossilsCount,
      actualSitesCount: actualSitesCount,
      email: email,
      fullName: fullName ?? this.fullName,
    );
  }
}
