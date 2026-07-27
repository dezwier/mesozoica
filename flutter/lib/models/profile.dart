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
  final bool isAdmin;
  final DateTime? createdAt;
  final double totalDistanceM;
  final double weeklyDistanceM;
  final double activeDistanceM;
  final double activeWeeklyDistanceM;

  final int explorationXp;
  final int excavationXp;
  final int researchXp;
  final int explorationLevel;
  final int excavationLevel;
  final int researchLevel;
  final String careerTitle;
  final double explorationProgress;
  final double excavationProgress;
  final double researchProgress;
  final double careerProgress;
  final int nextLevelXp;
  final int xpToNextLevel;
  final int xpFromSites;
  final int xpFromFossils;
  final int xpFromActiveDistance;
  final int xpFromPassiveDistance;

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
    this.isAdmin = false,
    this.createdAt,
    this.totalDistanceM = 0,
    this.weeklyDistanceM = 0,
    this.activeDistanceM = 0,
    this.activeWeeklyDistanceM = 0,
    this.explorationXp = 0,
    this.excavationXp = 0,
    this.researchXp = 0,
    this.explorationLevel = 1,
    this.excavationLevel = 1,
    this.researchLevel = 1,
    this.careerTitle = 'Trail Dust Note',
    this.explorationProgress = 0,
    this.excavationProgress = 0,
    this.researchProgress = 0,
    this.careerProgress = 0,
    this.nextLevelXp = 0,
    this.xpToNextLevel = 0,
    this.xpFromSites = 0,
    this.xpFromFossils = 0,
    this.xpFromActiveDistance = 0,
    this.xpFromPassiveDistance = 0,
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
      isAdmin: json['is_admin'] as bool? ??
          json['isAdmin'] as bool? ??
          false,
      createdAt: _parseDateTime(
        json['created_at'] ?? json['createdAt'],
      ),
      totalDistanceM: (json['total_distance_m'] as num?)?.toDouble() ??
          (json['totalDistanceM'] as num?)?.toDouble() ??
          0,
      weeklyDistanceM: (json['weekly_distance_m'] as num?)?.toDouble() ??
          (json['weeklyDistanceM'] as num?)?.toDouble() ??
          0,
      activeDistanceM: (json['active_distance_m'] as num?)?.toDouble() ??
          (json['activeDistanceM'] as num?)?.toDouble() ??
          0,
      activeWeeklyDistanceM:
          (json['active_weekly_distance_m'] as num?)?.toDouble() ??
              (json['activeWeeklyDistanceM'] as num?)?.toDouble() ??
              0,
      explorationXp: json['exploration_xp'] as int? ??
          json['explorationXp'] as int? ??
          0,
      excavationXp: json['excavation_xp'] as int? ??
          json['excavationXp'] as int? ??
          0,
      researchXp: json['research_xp'] as int? ?? json['researchXp'] as int? ?? 0,
      explorationLevel: json['exploration_level'] as int? ??
          json['explorationLevel'] as int? ??
          1,
      excavationLevel: json['excavation_level'] as int? ??
          json['excavationLevel'] as int? ??
          1,
      researchLevel: json['research_level'] as int? ??
          json['researchLevel'] as int? ??
          1,
      careerTitle: json['career_title'] as String? ??
          json['careerTitle'] as String? ??
          'Trail Dust Note',
      explorationProgress:
          (json['exploration_progress'] as num?)?.toDouble() ??
              (json['explorationProgress'] as num?)?.toDouble() ??
              0,
      excavationProgress: (json['excavation_progress'] as num?)?.toDouble() ??
          (json['excavationProgress'] as num?)?.toDouble() ??
          0,
      researchProgress: (json['research_progress'] as num?)?.toDouble() ??
          (json['researchProgress'] as num?)?.toDouble() ??
          0,
      careerProgress: (json['career_progress'] as num?)?.toDouble() ??
          (json['careerProgress'] as num?)?.toDouble() ??
          0,
      nextLevelXp: json['next_level_xp'] as int? ??
          json['nextLevelXp'] as int? ??
          0,
      xpToNextLevel: json['xp_to_next_level'] as int? ??
          json['xpToNextLevel'] as int? ??
          0,
      xpFromSites: json['xp_from_sites'] as int? ??
          json['xpFromSites'] as int? ??
          0,
      xpFromFossils: json['xp_from_fossils'] as int? ??
          json['xpFromFossils'] as int? ??
          0,
      xpFromActiveDistance: json['xp_from_active_distance'] as int? ??
          json['xpFromActiveDistance'] as int? ??
          0,
      xpFromPassiveDistance: json['xp_from_passive_distance'] as int? ??
          json['xpFromPassiveDistance'] as int? ??
          0,
    );
  }

  static DateTime? _parseDateTime(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw);
    }
    return null;
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
        'isAdmin': isAdmin,
        'createdAt': createdAt?.toIso8601String(),
        'totalDistanceM': totalDistanceM,
        'weeklyDistanceM': weeklyDistanceM,
        'activeDistanceM': activeDistanceM,
        'activeWeeklyDistanceM': activeWeeklyDistanceM,
        'explorationXp': explorationXp,
        'excavationXp': excavationXp,
        'researchXp': researchXp,
        'explorationLevel': explorationLevel,
        'excavationLevel': excavationLevel,
        'researchLevel': researchLevel,
        'careerTitle': careerTitle,
        'explorationProgress': explorationProgress,
        'excavationProgress': excavationProgress,
        'researchProgress': researchProgress,
        'careerProgress': careerProgress,
        'nextLevelXp': nextLevelXp,
        'xpToNextLevel': xpToNextLevel,
        'xpFromSites': xpFromSites,
        'xpFromFossils': xpFromFossils,
        'xpFromActiveDistance': xpFromActiveDistance,
        'xpFromPassiveDistance': xpFromPassiveDistance,
      };

  Profile copyWith({
    String? displayName,
    String? username,
    String? profileImage,
    String? fullName,
    bool? isAdmin,
    DateTime? createdAt,
    double? totalDistanceM,
    double? weeklyDistanceM,
    double? activeDistanceM,
    double? activeWeeklyDistanceM,
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
      isAdmin: isAdmin ?? this.isAdmin,
      createdAt: createdAt ?? this.createdAt,
      totalDistanceM: totalDistanceM ?? this.totalDistanceM,
      weeklyDistanceM: weeklyDistanceM ?? this.weeklyDistanceM,
      activeDistanceM: activeDistanceM ?? this.activeDistanceM,
      activeWeeklyDistanceM:
          activeWeeklyDistanceM ?? this.activeWeeklyDistanceM,
      explorationXp: explorationXp,
      excavationXp: excavationXp,
      researchXp: researchXp,
      explorationLevel: explorationLevel,
      excavationLevel: excavationLevel,
      researchLevel: researchLevel,
      careerTitle: careerTitle,
      explorationProgress: explorationProgress,
      excavationProgress: excavationProgress,
      researchProgress: researchProgress,
      careerProgress: careerProgress,
      nextLevelXp: nextLevelXp,
      xpToNextLevel: xpToNextLevel,
      xpFromSites: xpFromSites,
      xpFromFossils: xpFromFossils,
      xpFromActiveDistance: xpFromActiveDistance,
      xpFromPassiveDistance: xpFromPassiveDistance,
    );
  }
}
