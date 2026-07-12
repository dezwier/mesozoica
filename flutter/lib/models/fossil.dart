import '../utils/display_text.dart';

class FossilSummary {
  const FossilSummary({
    required this.id,
    required this.dinosaurId,
    required this.dinosaurName,
    this.identifiedName,
    this.countryCode,
    this.state,
    this.geologicalFormation,
    this.latitude,
    this.longitude,
    this.collectionName,
    this.collectionDates,
    this.stratcomments,
    this.lithdescript,
    this.description,
    this.collectors,
    this.museum,
    this.family,
    this.presMode,
    this.preservationQuality,
    this.abundValue,
    this.abundUnit,
    this.minAgeMa,
    this.maxAgeMa,
    this.earlyInterval,
    this.mainImageUrl,
    this.dinosaurMainImageUrl,
  });

  final int id;
  final int dinosaurId;
  final String dinosaurName;
  final String? identifiedName;
  final String? countryCode;
  final String? state;
  final String? geologicalFormation;
  final double? latitude;
  final double? longitude;
  final String? collectionName;
  final String? collectionDates;
  final String? stratcomments;
  final String? lithdescript;
  final String? description;
  final String? collectors;
  final String? museum;
  final String? family;
  final String? presMode;
  final String? preservationQuality;
  final int? abundValue;
  final String? abundUnit;
  final double? minAgeMa;
  final double? maxAgeMa;
  final String? earlyInterval;
  final String? mainImageUrl;
  final String? dinosaurMainImageUrl;

  factory FossilSummary.fromJson(Map<String, dynamic> json) {
    return FossilSummary(
      id: json['id'] as int,
      dinosaurId: json['dinosaur_id'] as int,
      dinosaurName: json['dinosaur_name'] as String,
      identifiedName: json['identified_name'] as String?,
      countryCode: json['country_code'] as String?,
      state: json['state'] as String?,
      geologicalFormation: json['geological_formation'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      collectionName: json['collection_name'] as String?,
      collectionDates: json['collection_dates'] as String?,
      stratcomments: json['stratcomments'] as String?,
      lithdescript: json['lithdescript'] as String?,
      description: json['description'] as String?,
      collectors: json['collectors'] as String?,
      museum: json['museum'] as String?,
      family: json['family'] as String?,
      presMode: json['pres_mode'] as String?,
      preservationQuality: json['preservation_quality'] as String?,
      abundValue: json['abund_value'] as int?,
      abundUnit: json['abund_unit'] as String?,
      minAgeMa: (json['min_age_ma'] as num?)?.toDouble(),
      maxAgeMa: (json['max_age_ma'] as num?)?.toDouble(),
      earlyInterval: json['early_interval'] as String?,
      mainImageUrl: json['main_image_url'] as String?,
      dinosaurMainImageUrl: json['dinosaur_main_image_url'] as String?,
    );
  }

  String get displayTitle {
    final identified = identifiedName?.trim();
    if (identified != null && identified.isNotEmpty) {
      return displayTaxonName(identified);
    }
    return dinosaurName;
  }

  String get displayCoordinates {
    if (latitude == null || longitude == null) return '—';
    final lat = latitude!.toStringAsFixed(4);
    final lng = longitude!.toStringAsFixed(4);
    return '$lat, $lng';
  }
}

class FossilListResponse {
  const FossilListResponse({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasNext,
  });

  final List<FossilSummary> items;
  final int total;
  final int limit;
  final int offset;
  final bool hasNext;

  bool get hasMore => hasNext;

  factory FossilListResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return FossilListResponse(
      items: rawItems
          .map((item) => FossilSummary.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? rawItems.length,
      limit: json['limit'] as int? ?? rawItems.length,
      offset: json['offset'] as int? ?? 0,
      hasNext: json['has_next'] as bool? ?? false,
    );
  }
}
