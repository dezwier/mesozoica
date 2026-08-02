import '../models/catalog_data_source.dart';
import 'app_config.dart';

/// API URI builders (split from [AppConfig] for readability).
class ApiEndpoints {
  ApiEndpoints._();

  static Uri dinosaursUri({
    int limit = 200,
    int offset = 0,
    String sort = 'name',
    String? seed,
    String? q,
    double? maYounger,
    double? maOlder,
    bool hasCustomImage = false,
    bool? llmEnriched,
    Set<String> diets = const {},
    double? lengthMMin,
    double? lengthMMax,
    double? massKgMin,
    double? massKgMax,
    String mode = 'catalog',
  }) {
    final parts = <String>[
      'limit=$limit',
      'offset=$offset',
      'sort=${Uri.encodeQueryComponent(sort)}',
      'mode=${Uri.encodeQueryComponent(mode)}',
    ];
    if (seed != null && seed.isNotEmpty) {
      parts.add('seed=${Uri.encodeQueryComponent(seed)}');
    }
    final trimmedQuery = q?.trim();
    if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
      parts.add('q=${Uri.encodeQueryComponent(trimmedQuery)}');
    }
    if (maYounger != null && maOlder != null) {
      parts.add('ma_younger=$maYounger');
      parts.add('ma_older=$maOlder');
    }
    if (hasCustomImage) {
      parts.add('has_custom_image=true');
    }
    if (llmEnriched != null) {
      parts.add('llm_enriched=${llmEnriched ? 'true' : 'false'}');
    }
    if (lengthMMin != null && lengthMMax != null) {
      parts.add('length_m_min=$lengthMMin');
      parts.add('length_m_max=$lengthMMax');
    }
    if (massKgMin != null && massKgMax != null) {
      parts.add('mass_kg_min=$massKgMin');
      parts.add('mass_kg_max=$massKgMax');
    }
    for (final value in diets) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      parts.add('diet=${Uri.encodeQueryComponent(trimmed)}');
    }
    return Uri.parse('${AppConfig.baseApiUrl}/api/v1/dinosaurs?${parts.join('&')}');
  }

  static Uri dinosaurArticleUri(int id) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/dinosaurs/$id/article');

  static Uri dinosaurUri(int id) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/dinosaurs/$id');

  static Uri dinosaurStatusUri(int id) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/dinosaurs/$id/status');

  static Uri dinosaurCollectUri(int id) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/dinosaurs/$id/collect');

  static Uri dinosaurDiscardUri(int id) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/dinosaurs/$id/discard');

  static Uri dinosaurImageVersionsUri() =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/dinosaurs/image-versions');

  static Uri fossilsUri({
    int limit = 200,
    int offset = 0,
    String sort = 'name',
    String? seed,
    String? q,
    String? dinoQ,
    String? fossilQ,
    double? maYounger,
    double? maOlder,
    bool hasCustomImage = false,
    bool hasCustomFossilImage = false,
    bool? llmEnriched,
    int? dinosaurId,
    CatalogDataSource dataSource = CatalogDataSource.archive,
    bool includeHidden = false,
  }) {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      'sort': sort,
    };
    if (seed != null && seed.isNotEmpty) {
      params['seed'] = seed;
    }
    final trimmedQuery = q?.trim();
    if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
      params['q'] = trimmedQuery;
    }
    final trimmedDinoQuery = dinoQ?.trim();
    if (trimmedDinoQuery != null && trimmedDinoQuery.isNotEmpty) {
      params['dino_q'] = trimmedDinoQuery;
    }
    final trimmedFossilQuery = fossilQ?.trim();
    if (trimmedFossilQuery != null && trimmedFossilQuery.isNotEmpty) {
      params['fossil_q'] = trimmedFossilQuery;
    }
    if (maYounger != null && maOlder != null) {
      params['ma_younger'] = '$maYounger';
      params['ma_older'] = '$maOlder';
    }
    if (hasCustomImage) {
      params['has_custom_image'] = 'true';
    }
    if (hasCustomFossilImage) {
      params['has_custom_fossil_image'] = 'true';
    }
    if (llmEnriched != null) {
      params['llm_enriched'] = llmEnriched ? 'true' : 'false';
    }
    if (dinosaurId != null) {
      params['dinosaur_id'] = '$dinosaurId';
    }
    params['data_source'] = dataSource.apiValue;
    if (includeHidden) {
      params['include_hidden'] = 'true';
    }
    return Uri.parse(
      '${AppConfig.baseApiUrl}/api/v1/fossils',
    ).replace(queryParameters: params);
  }

  static Uri fossilUri(
    int id, {
    CatalogDataSource dataSource = CatalogDataSource.archive,
  }) => Uri.parse(
    '${AppConfig.baseApiUrl}/api/v1/fossils/$id',
  ).replace(queryParameters: {'data_source': dataSource.apiValue});

  static Uri fossilStatusUri(int id) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/fossils/$id/status');

  static Uri fossilDiscardUri(int id) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/fossils/$id/discard');

  static Uri sitesUri({
    int limit = 200,
    int offset = 0,
    String sort = 'name',
    String? seed,
    String? q,
    double? maYounger,
    double? maOlder,
    bool hasCustomImage = false,
    CatalogDataSource dataSource = CatalogDataSource.archive,
    int? siteIdMin,
    bool showAll = false,
    List<String>? howDiscovered,
    DateTime? discoveredAfter,
    DateTime? discoveredBefore,
    double? lat,
    double? lon,
    double? minLat,
    double? maxLat,
    double? minLon,
    double? maxLon,
  }) {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      'sort': sort,
    };
    if (seed != null && seed.isNotEmpty) {
      params['seed'] = seed;
    }
    final trimmedQuery = q?.trim();
    if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
      params['q'] = trimmedQuery;
    }
    if (maYounger != null && maOlder != null) {
      params['ma_younger'] = '$maYounger';
      params['ma_older'] = '$maOlder';
    }
    if (hasCustomImage) {
      params['has_custom_image'] = 'true';
    }
    if (siteIdMin != null) {
      params['site_id_min'] = '$siteIdMin';
    }
    params['data_source'] = dataSource.apiValue;
    if (showAll) {
      params['show_all'] = 'true';
    }
    if (discoveredAfter != null) {
      params['discovered_after'] = discoveredAfter.toUtc().toIso8601String();
    }
    if (discoveredBefore != null) {
      params['discovered_before'] = discoveredBefore.toUtc().toIso8601String();
    }
    if (lat != null && lon != null) {
      params['lat'] = '$lat';
      params['lon'] = '$lon';
    }
    if (minLat != null && maxLat != null && minLon != null && maxLon != null) {
      params['min_lat'] = '$minLat';
      params['max_lat'] = '$maxLat';
      params['min_lon'] = '$minLon';
      params['max_lon'] = '$maxLon';
    }
    var uri = Uri.parse(
      '${AppConfig.baseApiUrl}/api/v1/sites',
    ).replace(queryParameters: params);
    final methods = howDiscovered;
    if (methods != null && methods.isNotEmpty) {
      final extras = methods
          .map((m) => 'how_discovered=${Uri.encodeQueryComponent(m)}')
          .join('&');
      final base = uri.toString();
      uri = Uri.parse(base.contains('?') ? '$base&$extras' : '$base?$extras');
    }
    return uri;
  }

  static Uri fieldSiteEnsureUri() =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/sites/field/ensure');

  static Uri fieldSiteEnsureJobUri(int jobId) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/sites/field/ensure/jobs/$jobId');

  static Uri fieldDataPurgeUri({
    bool userSites = true,
    bool userFossils = true,
    bool sites = true,
    bool fossils = true,
    bool sessionEvents = true,
    bool sessions = true,
  }) => Uri.parse('${AppConfig.baseApiUrl}/api/v1/sites/field').replace(
    queryParameters: {
      'user_sites': '$userSites',
      'user_fossils': '$userFossils',
      'sites': '$sites',
      'fossils': '$fossils',
      'session_events': '$sessionEvents',
      'sessions': '$sessions',
    },
  );

  static Uri siteUri(
    int id, {
    CatalogDataSource dataSource = CatalogDataSource.archive,
  }) => Uri.parse(
    '${AppConfig.baseApiUrl}/api/v1/sites/$id',
  ).replace(queryParameters: {'data_source': dataSource.apiValue});

  static Uri siteDiscoverUri(int id) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/sites/$id/discover');

  static Uri siteStatusUri(int id) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/sites/$id/status');

  static Uri siteDiscardUri(int id) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/sites/$id/discard');

  static Uri siteSurveyUri(int id) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/sites/$id/survey');

  static Uri fieldSurveyJobUri(int jobId) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/sites/survey/jobs/$jobId');

  static Uri sitesNearbyDiscoverableUri({
    required double lat,
    required double lon,
    double radiusKm = 1.0,
  }) {
    return Uri.parse('${AppConfig.baseApiUrl}/api/v1/sites/nearby-discoverable').replace(
      queryParameters: {'lat': '$lat', 'lon': '$lon', 'radius_km': '$radiusKm'},
    );
  }

  static Uri sitesNearbyUri({
    required double lat,
    required double lon,
    double radiusKm = 1.0,
    CatalogDataSource dataSource = CatalogDataSource.field,
    bool showAll = false,
  }) {
    final params = <String, String>{
      'lat': '$lat',
      'lon': '$lon',
      'radius_km': '$radiusKm',
      'data_source': dataSource.apiValue,
    };
    if (showAll) {
      params['show_all'] = 'true';
    }
    return Uri.parse(
      '${AppConfig.baseApiUrl}/api/v1/sites/nearby',
    ).replace(queryParameters: params);
  }

  static Uri siteFossilsUri(int siteId) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/sites/$siteId/fossils');

  static Uri siteDinosaursUri(int siteId) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/sites/$siteId/dinosaurs');

  static Uri siteGroupsUri(int siteId) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/sites/$siteId/groups');

  static Uri siteTypesUri({
    int limit = 200,
    int offset = 0,
  }) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/site-types').replace(
        queryParameters: {
          'limit': '$limit',
          'offset': '$offset',
        },
      );

  static Uri toolsUri({
    int limit = 200,
    int offset = 0,
    String sort = 'category',
    String mode = 'inventory',
    String? seed,
    String? q,
    Set<String> categories = const {},
    bool hasCustomImage = false,
    bool showAll = false,
  }) {
    final parts = <String>[
      'limit=$limit',
      'offset=$offset',
      'sort=${Uri.encodeQueryComponent(sort)}',
    ];
    parts.add('mode=${Uri.encodeQueryComponent(mode)}');
    if (seed != null && seed.isNotEmpty) {
      parts.add('seed=${Uri.encodeQueryComponent(seed)}');
    }
    final trimmedQuery = q?.trim();
    if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
      parts.add('q=${Uri.encodeQueryComponent(trimmedQuery)}');
    }
    if (hasCustomImage) {
      parts.add('has_custom_image=true');
    }
    if (showAll) {
      parts.add('show_all=true');
    }
    for (final value in categories) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      parts.add('category=${Uri.encodeQueryComponent(trimmed)}');
    }
    return Uri.parse('${AppConfig.baseApiUrl}/api/v1/tools?${parts.join('&')}');
  }

  static Uri toolCategoriesUri({
    bool showAll = false,
    String mode = 'inventory',
  }) {
    final parts = <String>['mode=${Uri.encodeQueryComponent(mode)}'];
    if (showAll) {
      parts.add('show_all=true');
    }
    return Uri.parse('${AppConfig.baseApiUrl}/api/v1/tools/categories?${parts.join('&')}');
  }

  static Uri toolUri(int id) => Uri.parse('${AppConfig.baseApiUrl}/api/v1/tools/$id');

  static Uri toolCollectUri(int id) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/tools/$id/collect');

  static Uri toolDiscardUri(int id) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/tools/$id/discard');

  static Uri toolImageVersionsUri() =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/tools/image-versions');

  static Uri toolSessionsUri(int toolId) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/tools/$toolId/sessions');

  static Uri activeToolSessionsUri({String? actionKey}) {
    final base = '${AppConfig.baseApiUrl}/api/v1/tools/sessions/active';
    if (actionKey == null || actionKey.isEmpty) {
      return Uri.parse(base);
    }
    return Uri.parse(
      '$base?action_key=${Uri.encodeQueryComponent(actionKey)}',
    );
  }

  static Uri toolSessionUri(int sessionId) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/tools/sessions/$sessionId');

  static Uri toolSessionCancelUri(int sessionId) =>
      Uri.parse('${AppConfig.baseApiUrl}/api/v1/tools/sessions/$sessionId/cancel');

}
