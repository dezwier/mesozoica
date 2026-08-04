import '../utils/display_text.dart';
import '../utils/period_for_ages.dart';
import '../utils/relative_time.dart';

export 'site_field.dart';
export 'site_related.dart';

/// Server-provided blurry display range for one site odd_* axis.
class SiteDimensionBand {
  const SiteDimensionBand({
    required this.rangeStart,
    required this.rangeEnd,
    required this.blurSigma,
    required this.effectiveAccuracy,
  });

  final double rangeStart;
  final double rangeEnd;
  final double blurSigma;
  final double effectiveAccuracy;

  factory SiteDimensionBand.fromJson(Map<String, dynamic> json) {
    return SiteDimensionBand(
      rangeStart: (json['range_start'] as num).toDouble(),
      rangeEnd: (json['range_end'] as num).toDouble(),
      blurSigma: (json['blur_sigma'] as num?)?.toDouble() ?? 0.0,
      effectiveAccuracy:
          (json['effective_accuracy'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

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
    this.viewerHasDocumented,
    this.viewerHasIdentified,
    this.discoveredAt,
    this.discoveringSessionId,
    this.viewerWasFirstDiscovery,
    this.documentedAt,
    this.viewerWasFirstDocumentation,
    this.oddDinoCount,
    this.oddFossilCount,
    this.oddCompleteness,
    this.oddQuality,
    this.oddDepth,
    this.oddDinoBand,
    this.oddFossilBand,
    this.oddCompletenessBand,
    this.oddQualityBand,
    this.oddDepthBand,
    this.exploredDistanceM,
    this.documented,
    this.version = 'Original',
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
  /// True when the viewing user has a documenter role on this site.
  final bool? viewerHasDocumented;
  /// True when the viewer finished period+rock identification (field sites).
  /// Archive sites are always treated as identified.
  final bool? viewerHasIdentified;
  /// When the viewing user became discoverer (from user_site).
  final DateTime? discoveredAt;
  /// Aerial session that discovered this site for the viewer.
  final int? discoveringSessionId;
  /// True when the viewer was the first discoverer of this site.
  final bool? viewerWasFirstDiscovery;
  /// When the viewing user completed documentation (documenter user_site).
  final DateTime? documentedAt;
  /// True when the viewer was the first to fully document this site.
  final bool? viewerWasFirstDocumentation;
  final double? oddDinoCount;
  final double? oddFossilCount;
  final double? oddCompleteness;
  final double? oddQuality;
  final double? oddDepth;
  final SiteDimensionBand? oddDinoBand;
  final SiteDimensionBand? oddFossilBand;
  final SiteDimensionBand? oddCompletenessBand;
  final SiteDimensionBand? oddQualityBand;
  final SiteDimensionBand? oddDepthBand;
  /// Meters walked inside site visibility (discoverer progress).
  final double? exploredDistanceM;
  /// True when all five dimension accuracies reached 100% (meters frozen).
  final bool? documented;
  /// Curated site-type image version folder for this occurrence.
  final String version;

  static const howDiscoveredWalk = 'walk';
  static const howDiscoveredAerialRecon = 'aerial_recon';
  static const howDiscoveredAerialScout = 'aerial_scout';
  static const howDiscoveredManual = 'manual';

  /// Field-generated site IDs start at 1_000_000_000; show the offset only.
  static const int fieldSiteIdBase = 1000000000;

  /// True for procedurally generated field sites (occurrence cards).
  bool get isFieldOccurrence => siteId >= fieldSiteIdBase;

  /// Short collection number for UI (`#67`, not `#1000000067`).
  static String formatSiteNumber(int siteId) {
    final n = siteId >= fieldSiteIdBase ? siteId - fieldSiteIdBase : siteId;
    return '#$n';
  }

  String get displaySiteNumber => formatSiteNumber(siteId);

  /// Front top-left badge: `#67 · Original`.
  String get occurrenceIdBadgeLabel {
    final versionPart = version.trim();
    if (versionPart.isEmpty) return displaySiteNumber;
    return '$displaySiteNumber · $versionPart';
  }

  String get displayTitle {
    if (needsIdentification) {
      return 'Excavation Site';
    }
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

  /// Field site discovered by the viewer but period/rock not yet identified.
  bool get needsIdentification =>
      isFieldOccurrence &&
      discoveredAt != null &&
      viewerHasIdentified != true;

  /// Identify quiz is available on the card back.
  bool get canIdentify => needsIdentification;

  /// Card-back subtitle when the viewer has discovered this site.
  /// Id and version are shown separately as [OccurrenceIdBadge] on the front.
  String? get discoveredSubtitle {
    final at = discoveredAt;
    if (at == null) return null;
    return 'Discovered ${formatRelativeWhen(at)}';
  }

  /// Subtitle: `#id, lat, lon, region, distance` (archive) or
  /// `lat, lon, region, distance` (field — id is a badge).
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
    if (parts.isEmpty) {
      return isFieldOccurrence ? '' : displaySiteNumber;
    }
    if (isFieldOccurrence) return parts.join(', ');
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

  static SiteDimensionBand? _bandFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    return SiteDimensionBand.fromJson(value);
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
      viewerHasDocumented: json['viewer_has_documented'] as bool?,
      viewerHasIdentified: json['viewer_has_identified'] as bool?,
      discoveredAt: _parseSiteDate(json['discovered_at']),
      discoveringSessionId: json['discovering_session_id'] as int?,
      viewerWasFirstDiscovery: json['viewer_was_first_discovery'] as bool?,
      documentedAt: _parseSiteDate(json['documented_at']),
      viewerWasFirstDocumentation:
          json['viewer_was_first_documentation'] as bool?,
      oddDinoCount: (json['odd_dino_count'] as num?)?.toDouble(),
      oddFossilCount: (json['odd_fossil_count'] as num?)?.toDouble(),
      oddCompleteness: (json['odd_completeness'] as num?)?.toDouble(),
      oddQuality: (json['odd_quality'] as num?)?.toDouble(),
      oddDepth: (json['odd_depth'] as num?)?.toDouble(),
      oddDinoBand: _bandFromJson(json['odd_dino_band']),
      oddFossilBand: _bandFromJson(json['odd_fossil_band']),
      oddCompletenessBand: _bandFromJson(json['odd_completeness_band']),
      oddQualityBand: _bandFromJson(json['odd_quality_band']),
      oddDepthBand: _bandFromJson(json['odd_depth_band']),
      exploredDistanceM: (json['explored_distance_m'] as num?)?.toDouble(),
      documented: json['documented'] as bool?,
      version: (json['version'] as String?)?.trim().isNotEmpty == true
          ? (json['version'] as String).trim()
          : 'Original',
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
    bool? viewerHasDocumented,
    bool? viewerHasIdentified,
    String? mainImageUrl,
    DateTime? discoveredAt,
    int? discoveringSessionId,
    bool? viewerWasFirstDiscovery,
    DateTime? documentedAt,
    bool? viewerWasFirstDocumentation,
    String? howDiscovered,
    double? exploredDistanceM,
    bool? documented,
    String? rockType,
    String? siteTypePeriod,
    String? siteTypeRockType,
    double? minAgeMa,
    double? maxAgeMa,
    SiteDimensionBand? oddDinoBand,
    SiteDimensionBand? oddFossilBand,
    SiteDimensionBand? oddCompletenessBand,
    SiteDimensionBand? oddQualityBand,
    SiteDimensionBand? oddDepthBand,
  }) {
    return SiteSummary(
      siteId: siteId,
      latitude: latitude,
      longitude: longitude,
      countryCode: countryCode,
      state: state,
      rockType: rockType ?? this.rockType,
      formation: formation,
      minAgeMa: minAgeMa ?? this.minAgeMa,
      maxAgeMa: maxAgeMa ?? this.maxAgeMa,
      siteTypeId: siteTypeId,
      siteTypePeriod: siteTypePeriod ?? this.siteTypePeriod,
      siteTypeRockType: siteTypeRockType ?? this.siteTypeRockType,
      mainImageUrl: mainImageUrl ?? this.mainImageUrl,
      howDiscovered: howDiscovered ?? this.howDiscovered,
      status: status ?? this.status,
      viewerHasDocumented: viewerHasDocumented ?? this.viewerHasDocumented,
      viewerHasIdentified: viewerHasIdentified ?? this.viewerHasIdentified,
      discoveredAt: discoveredAt ?? this.discoveredAt,
      discoveringSessionId:
          discoveringSessionId ?? this.discoveringSessionId,
      viewerWasFirstDiscovery:
          viewerWasFirstDiscovery ?? this.viewerWasFirstDiscovery,
      documentedAt: documentedAt ?? this.documentedAt,
      viewerWasFirstDocumentation:
          viewerWasFirstDocumentation ?? this.viewerWasFirstDocumentation,
      oddDinoCount: oddDinoCount,
      oddFossilCount: oddFossilCount,
      oddCompleteness: oddCompleteness,
      oddQuality: oddQuality,
      oddDepth: oddDepth,
      oddDinoBand: oddDinoBand ?? this.oddDinoBand,
      oddFossilBand: oddFossilBand ?? this.oddFossilBand,
      oddCompletenessBand: oddCompletenessBand ?? this.oddCompletenessBand,
      oddQualityBand: oddQualityBand ?? this.oddQualityBand,
      oddDepthBand: oddDepthBand ?? this.oddDepthBand,
      exploredDistanceM: exploredDistanceM ?? this.exploredDistanceM,
      documented: documented ?? this.documented,
      version: version,
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
