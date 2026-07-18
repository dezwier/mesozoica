import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../controllers/catalog_mode_controller.dart';
import '../models/site.dart';

class SiteService {
  SiteService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<SiteListResponse> fetchSites({
    int limit = 200,
    int offset = 0,
    String sort = 'name',
    String? seed,
    String? q,
    double? maYounger,
    double? maOlder,
    bool hasCustomImage = false,
    CatalogDataSource dataSource = CatalogDataSource.archive,
  }) async {
    final uri = AppConfig.sitesUri(
      limit: limit,
      offset: offset,
      sort: sort,
      seed: seed,
      q: q,
      maYounger: maYounger,
      maOlder: maOlder,
      hasCustomImage: hasCustomImage,
      dataSource: dataSource,
    );
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw SiteServiceException(
        'Failed to load sites (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid sites response');
    }
    return SiteListResponse.fromJson(decoded);
  }

  Future<SiteSummary> fetchSiteById(
    int id, {
    CatalogDataSource dataSource = CatalogDataSource.archive,
  }) async {
    final uri = AppConfig.siteUri(id, dataSource: dataSource);
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode == 404) {
      throw SiteServiceException('Site not found');
    }
    if (response.statusCode != 200) {
      throw SiteServiceException(
        'Failed to load site (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid site response');
    }
    return SiteSummary.fromJson(decoded);
  }

  Future<SiteNearbyResponse> fetchNearbySites({
    required double lat,
    required double lon,
    double radiusKm = 1.0,
    CatalogDataSource dataSource = CatalogDataSource.field,
  }) async {
    final uri = AppConfig.sitesNearbyUri(
      lat: lat,
      lon: lon,
      radiusKm: radiusKm,
      dataSource: dataSource,
    );
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw SiteServiceException(
        'Failed to load nearby sites (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid nearby sites response');
    }
    return SiteNearbyResponse.fromJson(decoded);
  }

  Future<List<SiteFossilThumb>> fetchFossilsForSite(int siteId) async {
    final uri = AppConfig.siteFossilsUri(siteId);
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw SiteServiceException(
        'Failed to load site fossils (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid site fossils response');
    }
    return SiteFossilThumbListResponse.fromJson(decoded).items;
  }

  Future<List<SiteDinosaurThumb>> fetchDinosaursForSite(int siteId) async {
    final uri = AppConfig.siteDinosaursUri(siteId);
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw SiteServiceException(
        'Failed to load site dinosaurs (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid site dinosaurs response');
    }
    return SiteDinosaurThumbListResponse.fromJson(decoded).items;
  }

  Future<List<SiteDinoFossilGroup>> fetchDinoFossilGroupsForSite(
    int siteId,
  ) async {
    final uri = AppConfig.siteGroupsUri(siteId);
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw SiteServiceException(
        'Failed to load site groups (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid site groups response');
    }
    return SiteDinoFossilGroupListResponse.fromJson(decoded).items;
  }

  void dispose() {
    _client.close();
  }
}

class SiteServiceException implements Exception {
  const SiteServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
