import '../utils/display_text.dart';
import '../utils/period_for_ages.dart';
import 'fossil.dart';

class SiteSummary {
  const SiteSummary({
    required this.siteId,
    this.latitude,
    this.longitude,
    this.countryCode,
    this.state,
    this.rockType,
    this.formation,
    this.minAgeMa,
    this.maxAgeMa,
    this.siteTypeId,
    this.siteTypePeriod,
    this.siteTypeRockType,
    this.mainImageUrl,
    this.howDiscovered,
    this.status,
    this.viewerHasSurveyed,
    this.discoveredAt,
    this.discoveringMissionId,
    this.oddDinoCount,
    this.oddFossilCount,
    this.oddCompleteness,
    this.oddQuality,
    this.oddDepth,
  });

  final int siteId;
  final double? latitude;
  final double? longitude;
  final String? countryCode;
  final String? state;
  final String? rockType;
  final String? formation;
  final double? minAgeMa;
  final double? maxAgeMa;
  final int? siteTypeId;
  final String? siteTypePeriod;
  final String? siteTypeRockType;
  final String? mainImageUrl;
  /// First discovery method: walk, aerial_recon, aerial_scout, or manual.
  final String? howDiscovered;
  final String? status;
  final bool? viewerHasSurveyed;
  /// When the viewing user became discoverer (from user_site).
  final DateTime? discoveredAt;
  /// Aerial mission that discovered this site for the viewer.
  final int? discoveringMissionId;
  final double? oddDinoCount;
  final double? oddFossilCount;
  final double? oddCompleteness;
  final double? oddQuality;
  final double? oddDepth;

  static const howDiscoveredWalk = 'walk';
  static const howDiscoveredAerialRecon = 'aerial_recon';
  static const howDiscoveredAerialScout = 'aerial_scout';
  static const howDiscoveredManual = 'manual';

  /// Field-generated site IDs start at 1_000_000_000; show the offset only.
  static const int fieldSiteIdBase = 1000000000;

  /// Short collection number for UI (`#67`, not `#1000000067`).
  static String formatSiteNumber(int siteId) {
    final n = siteId >= fieldSiteIdBase ? siteId - fieldSiteIdBase : siteId;
    return '#$n';
  }

  String get displaySiteNumber => formatSiteNumber(siteId);

  String get displayTitle {
    final period = effectivePeriod;
    final rock = (rockType ?? siteTypeRockType)?.trim();
    final parts = <String>[];
    if (period != null && period.isNotEmpty) {
      parts.add(toTitleCase(period));
    }
    if (rock != null && rock.isNotEmpty) {
      parts.add(toTitleCase(rock));
    }
    if (parts.isNotEmpty) {
      return parts.join(' ');
    }
    return displaySiteNumber;
  }

  /// Subtitle: `#id, lat, lon, region, distance`.
  ///
  /// [distanceMeters] is appended after region when known (e.g. `450m`, `1.23km`).
  String displaySubtitle({double? distanceMeters}) {
    final parts = <String>[];
    if (latitude != null && longitude != null) {
      parts.add(displayCoordinates);
    }
    final trimmedState = state?.trim();
    if (trimmedState != null && trimmedState.isNotEmpty) {
      parts.add(trimmedState);
    }
    final trimmedCountry = countryCode?.trim();
    if (trimmedCountry != null && trimmedCountry.isNotEmpty) {
      parts.add(trimmedCountry);
    }
    if (distanceMeters != null) {
      parts.add(formatSiteDistance(distanceMeters));
    }
    if (parts.isEmpty) return displaySiteNumber;
    return '$displaySiteNumber, ${parts.join(', ')}';
  }

  /// Formats a distance as `450m` (< 1 km) or `1.23km` (≥ 1 km).
  static String formatSiteDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()}m';
    }
    return '${(meters / 1000).toStringAsFixed(2)}km';
  }

  String get displayCoordinates {
    if (latitude == null || longitude == null) return '—';
    return '${latitude!.toStringAsFixed(2)}, ${longitude!.toStringAsFixed(2)}';
  }

  String get displayCountry {
    final parts = <String>[];
    final trimmedState = state?.trim();
    if (trimmedState != null && trimmedState.isNotEmpty) {
      parts.add(trimmedState);
    }
    final trimmedCountry = countryCode?.trim();
    if (trimmedCountry != null && trimmedCountry.isNotEmpty) {
      parts.add(trimmedCountry);
    }
    if (parts.isEmpty) return '—';
    return parts.join(', ');
  }

  /// Site type period when set, otherwise inferred from [minAgeMa]/[maxAgeMa].
  String? get effectivePeriod {
    final fromType = siteTypePeriod?.trim();
    if (fromType != null && fromType.isNotEmpty) {
      return fromType.toLowerCase();
    }
    return periodForAges(minAgeMa, maxAgeMa);
  }

  String get displayPeriod {
    final periodName = effectivePeriod;
    final capitalizedPeriod = periodName != null && periodName.isNotEmpty
        ? capitalizeLeadingLetter(periodName)
        : null;

    if (minAgeMa != null && maxAgeMa != null) {
      final maLabel = minAgeMa!.round() == maxAgeMa!.round()
          ? '${minAgeMa!.round()} Ma'
          : '${minAgeMa!.round()} – ${maxAgeMa!.round()} Ma';
      if (capitalizedPeriod != null) {
        return '$capitalizedPeriod, $maLabel';
      }
      return maLabel;
    }
    if (capitalizedPeriod != null) {
      return capitalizedPeriod;
    }
    return '—';
  }

  factory SiteSummary.fromJson(Map<String, dynamic> json) {
    return SiteSummary(
      siteId: json['site_id'] as int,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      countryCode: json['country_code'] as String?,
      state: json['state'] as String?,
      rockType: json['rock_type'] as String?,
      formation: json['formation'] as String?,
      minAgeMa: (json['min_age_ma'] as num?)?.toDouble(),
      maxAgeMa: (json['max_age_ma'] as num?)?.toDouble(),
      siteTypeId: json['site_type_id'] as int?,
      siteTypePeriod: json['site_type_period'] as String?,
      siteTypeRockType: json['site_type_rock_type'] as String?,
      mainImageUrl: json['main_image_url'] as String?,
      howDiscovered: json['how_discovered'] as String?,
      status: json['status'] as String?,
      viewerHasSurveyed: json['viewer_has_surveyed'] as bool?,
      discoveredAt: _parseSiteDate(json['discovered_at']),
      discoveringMissionId: json['discovering_mission_id'] as int?,
      oddDinoCount: (json['odd_dino_count'] as num?)?.toDouble(),
      oddFossilCount: (json['odd_fossil_count'] as num?)?.toDouble(),
      oddCompleteness: (json['odd_completeness'] as num?)?.toDouble(),
      oddQuality: (json['odd_quality'] as num?)?.toDouble(),
      oddDepth: (json['odd_depth'] as num?)?.toDouble(),
    );
  }

  static DateTime? _parseSiteDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final hasTz =
        value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
    final parsed = DateTime.tryParse(hasTz ? value : '${value}Z');
    return parsed?.toUtc();
  }

  SiteSummary copyWith({
    String? status,
    bool? viewerHasSurveyed,
    String? mainImageUrl,
    DateTime? discoveredAt,
    int? discoveringMissionId,
    String? howDiscovered,
  }) {
    return SiteSummary(
      siteId: siteId,
      latitude: latitude,
      longitude: longitude,
      countryCode: countryCode,
      state: state,
      rockType: rockType,
      formation: formation,
      minAgeMa: minAgeMa,
      maxAgeMa: maxAgeMa,
      siteTypeId: siteTypeId,
      siteTypePeriod: siteTypePeriod,
      siteTypeRockType: siteTypeRockType,
      mainImageUrl: mainImageUrl ?? this.mainImageUrl,
      howDiscovered: howDiscovered ?? this.howDiscovered,
      status: status ?? this.status,
      viewerHasSurveyed: viewerHasSurveyed ?? this.viewerHasSurveyed,
      discoveredAt: discoveredAt ?? this.discoveredAt,
      discoveringMissionId:
          discoveringMissionId ?? this.discoveringMissionId,
      oddDinoCount: oddDinoCount,
      oddFossilCount: oddFossilCount,
      oddCompleteness: oddCompleteness,
      oddQuality: oddQuality,
      oddDepth: oddDepth,
    );
  }
}

class SiteListResponse {
  const SiteListResponse({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasNext,
  });

  final List<SiteSummary> items;
  final int total;
  final int limit;
  final int offset;
  final bool hasNext;

  bool get hasMore => hasNext;

  factory SiteListResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return SiteListResponse(
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(SiteSummary.fromJson)
              .toList()
          : const [],
      total: json['total'] as int? ?? 0,
      limit: json['limit'] as int? ?? 0,
      offset: json['offset'] as int? ?? 0,
      hasNext: json['has_next'] as bool? ?? false,
    );
  }
}

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

class FieldSurveyResponse {
  const FieldSurveyResponse({
    required this.site,
    this.jobId,
    required this.status,
    this.onboarded = false,
    this.generated = false,
    this.fossilsReady = false,
  });

  final SiteSummary site;
  final int? jobId;
  final String status;
  final bool onboarded;
  final bool generated;
  final bool fossilsReady;

  factory FieldSurveyResponse.fromJson(Map<String, dynamic> json) {
    return FieldSurveyResponse(
      site: SiteSummary.fromJson(json['site'] as Map<String, dynamic>),
      jobId: json['job_id'] as int?,
      status: json['status'] as String? ?? 'pending',
      onboarded: json['onboarded'] as bool? ?? false,
      generated: json['generated'] as bool? ?? false,
      fossilsReady: json['fossils_ready'] as bool? ?? false,
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
    this.missionEventsDeleted = 0,
    this.missionsDeleted = 0,
  });

  final int userSitesDeleted;
  final int userFossilsDeleted;
  final int sitesDeleted;
  final int fossilsDeleted;
  final int surveyJobsDeleted;
  final int ensureJobsDeleted;
  final int missionEventsDeleted;
  final int missionsDeleted;

  factory FieldDataPurgeResult.fromJson(Map<String, dynamic> json) {
    return FieldDataPurgeResult(
      userSitesDeleted: json['user_sites_deleted'] as int? ?? 0,
      userFossilsDeleted: json['user_fossils_deleted'] as int? ?? 0,
      sitesDeleted: json['sites_deleted'] as int? ?? 0,
      fossilsDeleted: json['fossils_deleted'] as int? ?? 0,
      surveyJobsDeleted: json['survey_jobs_deleted'] as int? ?? 0,
      ensureJobsDeleted: json['ensure_jobs_deleted'] as int? ?? 0,
      missionEventsDeleted: json['mission_events_deleted'] as int? ?? 0,
      missionsDeleted: json['missions_deleted'] as int? ?? 0,
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

class SiteFossilThumb {
  const SiteFossilThumb({
    required this.id,
    this.mainImageUrl,
    this.identifiedName,
    this.status,
  });

  final int id;
  final String? mainImageUrl;
  final String? identifiedName;
  final String? status;

  bool get isHidden => (status ?? 'hidden').trim().toLowerCase() == 'hidden';

  String get displayLabel {
    final identified = identifiedName?.trim();
    if (identified != null && identified.isNotEmpty) {
      return displayTaxonName(identified);
    }
    return '#$id';
  }

  factory SiteFossilThumb.fromJson(Map<String, dynamic> json) {
    return SiteFossilThumb(
      id: json['id'] as int,
      mainImageUrl: json['main_image_url'] as String?,
      identifiedName: json['identified_name'] as String?,
      status: json['status'] as String?,
    );
  }
}

class SiteDinosaurThumb {
  const SiteDinosaurThumb({
    required this.id,
    required this.name,
    this.mainImageUrl,
  });

  final int id;
  final String name;
  final String? mainImageUrl;

  factory SiteDinosaurThumb.fromJson(Map<String, dynamic> json) {
    return SiteDinosaurThumb(
      id: json['id'] as int,
      name: json['name'] as String,
      mainImageUrl: json['main_image_url'] as String?,
    );
  }
}

class SiteFossilThumbListResponse {
  const SiteFossilThumbListResponse({required this.items});

  final List<SiteFossilThumb> items;

  factory SiteFossilThumbListResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return SiteFossilThumbListResponse(
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(SiteFossilThumb.fromJson)
              .toList()
          : const [],
    );
  }
}

class SiteDinosaurThumbListResponse {
  const SiteDinosaurThumbListResponse({required this.items});

  final List<SiteDinosaurThumb> items;

  factory SiteDinosaurThumbListResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return SiteDinosaurThumbListResponse(
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(SiteDinosaurThumb.fromJson)
              .toList()
          : const [],
    );
  }
}

class SiteDinoFossilGroup {
  const SiteDinoFossilGroup({
    required this.dinosaur,
    required this.fossils,
  });

  final SiteDinosaurThumb dinosaur;
  final List<SiteFossilThumb> fossils;

  factory SiteDinoFossilGroup.fromJson(Map<String, dynamic> json) {
    final rawFossils = json['fossils'];
    return SiteDinoFossilGroup(
      dinosaur: SiteDinosaurThumb.fromJson(
        json['dinosaur'] as Map<String, dynamic>,
      ),
      fossils: rawFossils is List
          ? rawFossils
              .whereType<Map<String, dynamic>>()
              .map(SiteFossilThumb.fromJson)
              .toList()
          : const [],
    );
  }
}

class SiteDinoFossilGroupListResponse {
  const SiteDinoFossilGroupListResponse({required this.items});

  final List<SiteDinoFossilGroup> items;

  factory SiteDinoFossilGroupListResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return SiteDinoFossilGroupListResponse(
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(SiteDinoFossilGroup.fromJson)
              .toList()
          : const [],
    );
  }
}
