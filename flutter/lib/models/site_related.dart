import '../utils/display_text.dart';

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
