class SkillState {
  const SkillState({
    required this.id,
    required this.name,
    required this.xp,
    required this.level,
    required this.nextLevelXp,
    required this.xpToNext,
    required this.progress,
  });

  final String id;
  final String name;
  final int xp;
  final int level;
  final int nextLevelXp;
  final int xpToNext;
  final double progress;

  factory SkillState.fromJson(Map<String, dynamic> json) {
    return SkillState(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      xp: json['xp'] as int? ?? 0,
      level: json['level'] as int? ?? 1,
      nextLevelXp: json['next_level_xp'] as int? ??
          json['nextLevelXp'] as int? ??
          0,
      xpToNext: json['xp_to_next'] as int? ?? json['xpToNext'] as int? ?? 0,
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CareerState {
  const CareerState({
    required this.xp,
    required this.level,
    required this.title,
    required this.nextLevelXp,
    required this.xpToNext,
    required this.progress,
  });

  final int xp;
  final int level;
  final String title;
  final int nextLevelXp;
  final int xpToNext;
  final double progress;

  factory CareerState.fromJson(Map<String, dynamic> json) {
    return CareerState(
      xp: json['xp'] as int? ?? 0,
      level: json['level'] as int? ?? 1,
      title: json['title'] as String? ?? 'Curious Wanderer',
      nextLevelXp: json['next_level_xp'] as int? ??
          json['nextLevelXp'] as int? ??
          0,
      xpToNext: json['xp_to_next'] as int? ?? json['xpToNext'] as int? ?? 0,
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
    );
  }
}

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
  /// Local Monday (yyyy-MM-dd) the weekly counters belong to, if known.
  final String? distanceWeekStart;

  final String careerTitle;
  final List<SkillState> skills;
  final CareerState? career;
  final Map<String, Map<String, int>> skillBreakdown;

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
    this.distanceWeekStart,
    this.careerTitle = 'Curious Wanderer',
    this.skills = const [],
    this.career,
    this.skillBreakdown = const {},
  });

  CareerState get effectiveCareer =>
      career ??
      CareerState(
        xp: xp,
        level: level,
        title: careerTitle,
        nextLevelXp: 0,
        xpToNext: 0,
        progress: 0,
      );

  factory Profile.fromJson(Map<String, dynamic> json) {
    final careerJson = json['career'];
    final career = careerJson is Map<String, dynamic>
        ? CareerState.fromJson(careerJson)
        : null;
    final skillsRaw = json['skills'] as List<dynamic>?;
    final breakdownRaw = json['skill_breakdown'] ?? json['skillBreakdown'];

    return Profile(
      id: json['id'] as int? ?? 0,
      displayName: json['display_name'] as String? ??
          json['displayName'] as String? ??
          'Unknown User',
      username: json['username'] as String?,
      xp: career?.xp ?? json['xp'] as int? ?? 0,
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
      level: career?.level ?? json['level'] as int? ?? 1,
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
      distanceWeekStart: _parseDateOnly(
        json['distance_week_start'] ?? json['distanceWeekStart'],
      ),
      careerTitle: career?.title ??
          json['career_title'] as String? ??
          json['careerTitle'] as String? ??
          'Curious Wanderer',
      skills: skillsRaw
              ?.whereType<Map<String, dynamic>>()
              .map(SkillState.fromJson)
              .toList() ??
          const [],
      career: career,
      skillBreakdown: _parseSkillBreakdown(breakdownRaw),
    );
  }

  static Map<String, Map<String, int>> _parseSkillBreakdown(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, Map<String, int>>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is Map) {
        out[entry.key.toString()] = {
          for (final inner in value.entries)
            inner.key.toString(): (inner.value as num?)?.toInt() ?? 0,
        };
      }
    }
    return out;
  }

  static DateTime? _parseDateTime(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  /// ISO calendar date (yyyy-MM-dd), or null if missing/invalid.
  static String? _parseDateOnly(Object? raw) {
    if (raw == null) return null;
    if (raw is String && raw.isNotEmpty) {
      // Accept full timestamps by taking the date prefix.
      final datePart = raw.length >= 10 ? raw.substring(0, 10) : raw;
      final parsed = DateTime.tryParse(datePart);
      if (parsed == null) return null;
      final y = parsed.year.toString().padLeft(4, '0');
      final m = parsed.month.toString().padLeft(2, '0');
      final d = parsed.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
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
        'distanceWeekStart': distanceWeekStart,
        'careerTitle': careerTitle,
        'skills': skills
            .map(
              (s) => {
                'id': s.id,
                'name': s.name,
                'xp': s.xp,
                'level': s.level,
                'nextLevelXp': s.nextLevelXp,
                'xpToNext': s.xpToNext,
                'progress': s.progress,
              },
            )
            .toList(),
        'career': {
          'xp': effectiveCareer.xp,
          'level': effectiveCareer.level,
          'title': effectiveCareer.title,
          'nextLevelXp': effectiveCareer.nextLevelXp,
          'xpToNext': effectiveCareer.xpToNext,
          'progress': effectiveCareer.progress,
        },
        'skillBreakdown': skillBreakdown,
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
    String? distanceWeekStart,
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
      distanceWeekStart: distanceWeekStart ?? this.distanceWeekStart,
      careerTitle: careerTitle,
      skills: skills,
      career: career,
      skillBreakdown: skillBreakdown,
    );
  }
}
