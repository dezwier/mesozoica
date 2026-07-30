import '../utils/display_text.dart';
import '../utils/period_for_ages.dart';
import '../utils/relative_time.dart';

export 'site_field.dart';
export 'site_related.dart';

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

  /// Front top-right badge: `#67 · Original`.
  String get occurrenceIdBadgeLabel {
    final versionPart = version.trim();
    if (versionPart.isEmpty) return displaySiteNumber;
    return '$displaySiteNumber · $versionPart';
  }

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
