import '../utils/display_text.dart';
import '../utils/period_for_ages.dart';

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

  String get displayTitle {
    final trimmed = formation?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return 'Site #$siteId';
  }

  String get displaySubtitle => 'Collection #$siteId';

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
    this.existingInRadius,
    this.missing,
    required this.radiusKm,
  });

  final bool accepted;
  final int? existingInRadius;
  final int? missing;
  final double radiusKm;

  factory FieldEnsureResponse.fromJson(Map<String, dynamic> json) {
    return FieldEnsureResponse(
      accepted: json['accepted'] as bool? ?? false,
      existingInRadius: json['existing_in_radius'] as int?,
      missing: json['missing'] as int?,
      radiusKm: (json['radius_km'] as num?)?.toDouble() ?? 1.0,
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
  });

  final int id;
  final String? mainImageUrl;
  final String? identifiedName;

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
