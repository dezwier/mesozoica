import 'fossil.dart';
import 'profile.dart';
import 'site.dart' show SiteSummary;

class FieldEnsureResponse {
  const FieldEnsureResponse({
    required this.accepted,
    this.jobId,
    this.status,
    this.existingInRadius,
    this.missing,
    this.generated,
    this.totalInRadius,
    required this.radiusKm,
    this.errorMessage,
  });

  final bool accepted;
  final int? jobId;
  final String? status;
  final int? existingInRadius;
  final int? missing;
  final int? generated;
  final int? totalInRadius;
  final double radiusKm;
  final String? errorMessage;

  factory FieldEnsureResponse.fromJson(Map<String, dynamic> json) {
    return FieldEnsureResponse(
      accepted: json['accepted'] as bool? ?? false,
      jobId: json['job_id'] as int?,
      status: json['status'] as String?,
      existingInRadius: json['existing_in_radius'] as int?,
      missing: json['missing'] as int?,
      generated: json['generated'] as int?,
      totalInRadius: json['total_in_radius'] as int?,
      radiusKm: (json['radius_km'] as num?)?.toDouble() ?? 1.0,
      errorMessage: json['error_message'] as String?,
    );
  }
}

class FieldEnsureJobStatus {
  const FieldEnsureJobStatus({
    required this.jobId,
    required this.status,
    this.generated,
    this.totalInRadius,
    required this.radiusKm,
    this.errorMessage,
  });

  final int jobId;
  final String status;
  final int? generated;
  final int? totalInRadius;
  final double radiusKm;
  final String? errorMessage;

  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';
  bool get isTerminal => isDone || isFailed;

  factory FieldEnsureJobStatus.fromJson(Map<String, dynamic> json) {
    return FieldEnsureJobStatus(
      jobId: json['job_id'] as int? ?? 0,
      status: json['status'] as String? ?? 'pending',
      generated: json['generated'] as int?,
      totalInRadius: json['total_in_radius'] as int?,
      radiusKm: (json['radius_km'] as num?)?.toDouble() ?? 1.0,
      errorMessage: json['error_message'] as String?,
    );
  }
}

class FieldDiscoverResponse {
  const FieldDiscoverResponse({
    required this.site,
    this.jobId,
    required this.status,
    this.onboarded = false,
    this.generated = false,
    this.fossilsReady = false,
    this.surfaceFossils = const [],
  });

  final SiteSummary site;
  final int? jobId;
  final String status;
  final bool onboarded;
  final bool generated;
  final bool fossilsReady;
  final List<FossilSummary> surfaceFossils;

  factory FieldDiscoverResponse.fromJson(Map<String, dynamic> json) {
    final rawFossils = json['surface_fossils'];
    final fossils = <FossilSummary>[];
    if (rawFossils is List) {
      for (final item in rawFossils) {
        if (item is Map<String, dynamic>) {
          fossils.add(FossilSummary.fromJson(item));
        }
      }
    }
    return FieldDiscoverResponse(
      site: SiteSummary.fromJson(json['site'] as Map<String, dynamic>),
      jobId: json['job_id'] as int?,
      status: json['status'] as String? ?? 'pending',
      onboarded: json['onboarded'] as bool? ?? false,
      generated: json['generated'] as bool? ?? false,
      fossilsReady: json['fossils_ready'] as bool? ?? false,
      surfaceFossils: fossils,
    );
  }
}

class SiteIdentifyOptions {
  const SiteIdentifyOptions({
    required this.step,
    required this.choices,
    required this.answer,
    this.periodIdentified = false,
    this.rockIdentified = false,
    this.identified = false,
    this.disabledGuesses = const [],
    this.choiceImages = const {},
  });

  final String step;
  final List<String> choices;

  /// Correct choice for this step (for instant local feedback).
  final String answer;
  final bool periodIdentified;
  final bool rockIdentified;
  final bool identified;
  final List<String> disabledGuesses;

  /// Original-folder site-type image URLs keyed by rock_type choice.
  final Map<String, String> choiceImages;

  factory SiteIdentifyOptions.fromJson(Map<String, dynamic> json) {
    final raw = json['choices'];
    final rawImages = json['choice_images'];
    final images = <String, String>{};
    if (rawImages is Map) {
      for (final entry in rawImages.entries) {
        final key = entry.key?.toString().toLowerCase();
        final value = entry.value?.toString().trim();
        if (key != null &&
            key.isNotEmpty &&
            value != null &&
            value.isNotEmpty) {
          images[key] = value;
        }
      }
    }
    final choices = raw is List
        ? raw.whereType<String>().map((e) => e.toLowerCase()).toList()
        : const <String>[];
    final answer = (json['answer'] as String?)?.trim().toLowerCase() ?? '';
    return SiteIdentifyOptions(
      step: json['step'] as String? ?? 'period',
      choices: choices,
      answer: answer,
      periodIdentified: json['period_identified'] as bool? ?? false,
      rockIdentified: json['rock_identified'] as bool? ?? false,
      identified: json['identified'] as bool? ?? false,
      disabledGuesses: (json['disabled_guesses'] is List)
          ? (json['disabled_guesses'] as List)
                .whereType<String>()
                .map((e) => e.toLowerCase())
                .toList()
          : const [],
      choiceImages: images,
    );
  }
}

class SiteIdentifyResult {
  const SiteIdentifyResult({
    required this.correct,
    required this.step,
    required this.site,
    required this.profile,
    this.message,
    this.disabledGuesses = const [],
    this.xpAwarded = 0,
    this.periodIdentified = false,
    this.rockIdentified = false,
    this.identified = false,
  });

  final bool correct;
  final String step;
  final String? message;
  final List<String> disabledGuesses;
  final int xpAwarded;
  final bool periodIdentified;
  final bool rockIdentified;
  final bool identified;
  final SiteSummary site;
  final Profile profile;

  factory SiteIdentifyResult.fromJson(Map<String, dynamic> json) {
    return SiteIdentifyResult(
      correct: json['correct'] as bool? ?? false,
      step: json['step'] as String? ?? 'period',
      message: json['message'] as String?,
      disabledGuesses: (json['disabled_guesses'] is List)
          ? (json['disabled_guesses'] as List)
                .whereType<String>()
                .map((e) => e.toLowerCase())
                .toList()
          : const [],
      xpAwarded: json['xp_awarded'] as int? ?? 0,
      periodIdentified: json['period_identified'] as bool? ?? false,
      rockIdentified: json['rock_identified'] as bool? ?? false,
      identified: json['identified'] as bool? ?? false,
      site: SiteSummary.fromJson(json['site'] as Map<String, dynamic>),
      profile: Profile.fromJson(json['profile'] as Map<String, dynamic>),
    );
  }
}

class FieldSurveyJobStatus {
  const FieldSurveyJobStatus({
    required this.jobId,
    required this.siteId,
    required this.status,
    this.fossilCount,
    this.errorMessage,
  });

  final int jobId;
  final int siteId;
  final String status;
  final int? fossilCount;
  final String? errorMessage;

  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';
  bool get isTerminal => isDone || isFailed;

  factory FieldSurveyJobStatus.fromJson(Map<String, dynamic> json) {
    return FieldSurveyJobStatus(
      jobId: json['job_id'] as int,
      siteId: json['site_id'] as int,
      status: json['status'] as String? ?? 'pending',
      fossilCount: json['fossil_count'] as int?,
      errorMessage: json['error_message'] as String?,
    );
  }
}

class FieldDataPurgeResult {
  const FieldDataPurgeResult({
    this.userSitesDeleted = 0,
    this.userFossilsDeleted = 0,
    required this.sitesDeleted,
    required this.fossilsDeleted,
    required this.surveyJobsDeleted,
    required this.ensureJobsDeleted,
    this.sessionEventsDeleted = 0,
    this.sessionsDeleted = 0,
    this.usersXpCleared = 0,
    this.clearedXp = 0,
  });

  final int userSitesDeleted;
  final int userFossilsDeleted;
  final int sitesDeleted;
  final int fossilsDeleted;
  final int surveyJobsDeleted;
  final int ensureJobsDeleted;
  final int sessionEventsDeleted;
  final int sessionsDeleted;
  final int usersXpCleared;
  final int clearedXp;

  factory FieldDataPurgeResult.fromJson(Map<String, dynamic> json) {
    return FieldDataPurgeResult(
      userSitesDeleted: json['user_sites_deleted'] as int? ?? 0,
      userFossilsDeleted: json['user_fossils_deleted'] as int? ?? 0,
      sitesDeleted: json['sites_deleted'] as int? ?? 0,
      fossilsDeleted: json['fossils_deleted'] as int? ?? 0,
      surveyJobsDeleted: json['survey_jobs_deleted'] as int? ?? 0,
      ensureJobsDeleted: json['ensure_jobs_deleted'] as int? ?? 0,
      sessionEventsDeleted: json['session_events_deleted'] as int? ?? 0,
      sessionsDeleted: json['sessions_deleted'] as int? ?? 0,
      usersXpCleared: json['users_xp_cleared'] as int? ?? 0,
      clearedXp: json['cleared_xp'] as int? ?? 0,
    );
  }
}

class SiteNearbyResponse {
  const SiteNearbyResponse({
    required this.items,
    required this.total,
    required this.generated,
    required this.radiusKm,
  });

  final List<SiteSummary> items;
  final int total;
  final int generated;
  final double radiusKm;

  factory SiteNearbyResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return SiteNearbyResponse(
      items: rawItems is List
          ? rawItems
                .whereType<Map<String, dynamic>>()
                .map(SiteSummary.fromJson)
                .toList()
          : const [],
      total: json['total'] as int? ?? 0,
      generated: json['generated'] as int? ?? 0,
      radiusKm: (json['radius_km'] as num?)?.toDouble() ?? 1.0,
    );
  }
}
