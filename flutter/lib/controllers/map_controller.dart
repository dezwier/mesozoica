import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../controllers/catalog_mode_controller.dart';
import '../models/site.dart';
import '../services/site_service.dart';

class MapController extends ChangeNotifier {
  MapController({
    SiteService? service,
    CatalogModeController? catalogModeController,
  })  : _service = service ?? SiteService(),
        _catalogModeController = catalogModeController;

  static const pageSize = 500;
  static const nearbyRadiusKm = 1.0;
  static const ensureMoveThresholdM = 500.0;

  final SiteService _service;
  final CatalogModeController? _catalogModeController;
  final Random _random = Random();
  final Distance _distance = const Distance();
  String? _seed;

  List<SiteSummary> _geoSites = [];
  bool _loading = false;
  bool _loadingComplete = false;
  String? _error;
  SiteSummary? _selectedSite;
  LatLngBounds? _siteBounds;
  int _loadSeq = 0;
  int _offset = 0;
  int _totalCatalog = 0;
  int _loadedCatalog = 0;
  LatLng? _lastEnsurePosition;
  bool _ensureInFlight = false;

  List<SiteSummary> get geoSites => List.unmodifiable(_geoSites);
  bool get loading => _loading;
  bool get loadingComplete => _loadingComplete;
  bool get isLoadingMore => _loading && _geoSites.isNotEmpty;
  String? get error => _error;
  SiteSummary? get selectedSite => _selectedSite;
  LatLngBounds? get siteBounds => _siteBounds;
  int get totalCatalog => _totalCatalog;
  int get loadedCatalog => _loadedCatalog;
  int get geoSiteCount => _geoSites.length;
  bool get isEmpty =>
      !_loading && _loadingComplete && _error == null && _geoSites.isEmpty;

  CatalogDataSource get _dataSource =>
      _catalogModeController?.dataSource ?? CatalogDataSource.archive;

  bool get _isFieldMode => _dataSource == CatalogDataSource.field;

  /// Starts or resumes background site pagination without blocking the map UI.
  void load({bool force = false}) {
    if (_isFieldMode) {
      _loadFieldMode(force: force);
      return;
    }

    if (!force) {
      if (_loading || _loadingComplete) return;
    } else {
      _resetCatalogState();
      _seed = _newSeed();
    }

    _seed ??= _newSeed();

    final seq = ++_loadSeq;
    _loading = true;
    _error = null;
    notifyListeners();

    unawaited(_loadPages(seq));
  }

  void _loadFieldMode({required bool force}) {
    if (!force && (_loading || _loadingComplete || _ensureInFlight)) {
      return;
    }
    if (force) {
      _resetCatalogState();
      _lastEnsurePosition = null;
    }
    _loadingComplete = false;
    _loading = false;
    _error = null;
    notifyListeners();
  }

  void pause() {
    if (!_loading && _loadingComplete) return;
    _loadSeq++;
    _loading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    load(force: true);
  }

  /// Ensures persisted field sites exist near [position] (500 m throttle).
  Future<void> ensureNearbySites(LatLng position) async {
    if (!_isFieldMode) return;
    if (_ensureInFlight) return;

    if (_lastEnsurePosition != null &&
        _distance(_lastEnsurePosition!, position) < ensureMoveThresholdM) {
      return;
    }

    _ensureInFlight = true;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _service.fetchNearbySites(
        lat: position.latitude,
        lon: position.longitude,
        radiusKm: nearbyRadiusKm,
        dataSource: CatalogDataSource.field,
      );
      _mergeSites(_withCoordinates(response.items));
      _lastEnsurePosition = position;
      _loadingComplete = true;
      _error = null;

      if (kDebugMode) {
        debugPrint(
          'MapController: ensured ${response.generated} new field sites; '
          '${response.total} within ${response.radiusKm} km',
        );
      }
    } on SiteServiceException catch (error) {
      _error = error.message;
    } catch (error) {
      _error =
          'Could not reach the API at ${AppConfig.baseApiUrl}. '
          'Check your connection or try again later.';
      if (kDebugMode) {
        debugPrint('MapController.ensureNearbySites failed: $error');
      }
    } finally {
      _ensureInFlight = false;
      _loading = false;
      notifyListeners();
    }
  }

  void selectSite(SiteSummary site) {
    _selectedSite = site;
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedSite == null) return;
    _selectedSite = null;
    notifyListeners();
  }

  /// Loads the latest site row so formation and other card fields are current.
  Future<SiteSummary> siteForDisplay(SiteSummary site) async {
    try {
      final fresh = await _service.fetchSiteById(
        site.siteId,
        dataSource: _dataSource,
      );
      _replaceCachedSite(fresh);
      return fresh;
    } on SiteServiceException {
      return site;
    } catch (_) {
      return site;
    }
  }

  void _replaceCachedSite(SiteSummary site) {
    final index = _geoSites.indexWhere((s) => s.siteId == site.siteId);
    if (index < 0) return;
    final updated = [..._geoSites];
    updated[index] = site;
    _geoSites = updated;
    if (_selectedSite?.siteId == site.siteId) {
      _selectedSite = site;
    }
    notifyListeners();
  }

  void _mergeSites(List<SiteSummary> incoming) {
    if (incoming.isEmpty) return;
    final byId = {for (final site in _geoSites) site.siteId: site};
    for (final site in incoming) {
      byId[site.siteId] = site;
    }
    _geoSites = byId.values.toList();
    _siteBounds = _expandBounds(_siteBounds, incoming);
  }

  void _resetCatalogState() {
    _geoSites = [];
    _siteBounds = null;
    _selectedSite = null;
    _offset = 0;
    _loadedCatalog = 0;
    _totalCatalog = 0;
    _loadingComplete = false;
  }

  Future<void> _loadPages(int seq) async {
    try {
      var hasMore = true;

      while (hasMore) {
        if (seq != _loadSeq) return;

        final response = await _fetchPage(offset: _offset);
        if (seq != _loadSeq) return;

        final geo = _withCoordinates(response.items);

        _geoSites = [..._geoSites, ...geo];
        _offset += response.items.length;
        _loadedCatalog = _offset;
        _totalCatalog = response.total;
        _siteBounds = _expandBounds(_siteBounds, geo);
        _error = null;
        notifyListeners();

        hasMore = response.hasMore;
        if (response.items.isEmpty) {
          hasMore = false;
        }

        if (kDebugMode) {
          debugPrint(
            'MapController: page loaded — ${_geoSites.length} geo sites '
            '($_loadedCatalog/$_totalCatalog catalog)',
          );
        }

        if (hasMore) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      if (seq != _loadSeq) return;
      _loadingComplete = true;

      if (kDebugMode) {
        debugPrint(
          'MapController: finished — ${_geoSites.length} geo sites '
          'from $_loadedCatalog catalog rows',
        );
      }
    } on SiteServiceException catch (error) {
      if (seq != _loadSeq) return;
      _error = error.message;
    } catch (error) {
      if (seq != _loadSeq) return;
      _error =
          'Could not reach the API at ${AppConfig.baseApiUrl}. '
          'Check your connection or try again later.';
      if (kDebugMode) {
        debugPrint('MapController.load failed: $error');
      }
    } finally {
      if (seq == _loadSeq) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<SiteListResponse> _fetchPage({required int offset}) async {
    final seed = _seed;
    if (seed == null || seed.isEmpty) {
      throw StateError('Map catalog seed missing before fetch');
    }
    return _service.fetchSites(
      limit: pageSize,
      offset: offset,
      sort: 'random',
      seed: seed,
      dataSource: _dataSource,
    );
  }

  String _newSeed() {
    return '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';
  }

  List<SiteSummary> _withCoordinates(List<SiteSummary> sites) {
    return sites
        .where(
          (site) => site.latitude != null && site.longitude != null,
        )
        .toList();
  }

  LatLngBounds? _expandBounds(
    LatLngBounds? existing,
    List<SiteSummary> sites,
  ) {
    if (sites.isEmpty) return existing;

    var minLat = existing?.southWest.latitude ?? sites.first.latitude!;
    var maxLat = existing?.northEast.latitude ?? sites.first.latitude!;
    var minLng = existing?.southWest.longitude ?? sites.first.longitude!;
    var maxLng = existing?.northEast.longitude ?? sites.first.longitude!;

    for (final site in sites) {
      final lat = site.latitude!;
      final lng = site.longitude!;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    return LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );
  }

  @override
  void dispose() {
    _loadSeq++;
    _service.dispose();
    super.dispose();
  }
}
