import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../controllers/catalog_mode_controller.dart';
import '../models/site.dart';
import '../services/site_service.dart';
import '../widgets/map/site_map_filters.dart';

/// Separate map caches so archive / field-linked / field-show-all switch
/// instantly like archive ↔ field, without reloading.
enum _MapCacheKey { archive, fieldLinked, fieldShowAll }

class _CatalogSnapshot {
  List<SiteSummary> geoSites = [];
  bool loading = false;
  bool loadingComplete = false;
  String? error;
  LatLngBounds? siteBounds;
  int offset = 0;
  int totalCatalog = 0;
  int loadedCatalog = 0;
  int maxFieldSiteId = 0;
  String? seed;
  int loadSeq = 0;

  void reset({required bool clearSeed}) {
    geoSites = [];
    siteBounds = null;
    offset = 0;
    loadedCatalog = 0;
    totalCatalog = 0;
    loadingComplete = false;
    loading = false;
    error = null;
    maxFieldSiteId = 0;
    if (clearSeed) {
      seed = null;
    }
  }
}

class MapController extends ChangeNotifier {
  MapController({
    SiteService? service,
    CatalogModeController? catalogModeController,
  })  : _service = service ?? SiteService(),
        _catalogModeController = catalogModeController;

  static const pageSize = 500;
  static const fieldPollInterval = Duration(seconds: 60);
  /// Aggressive polling while a generation job is expected to be writing.
  static const _fieldPollBurstDelays = [
    Duration(seconds: 3),
    Duration(seconds: 6),
    Duration(seconds: 10),
    Duration(seconds: 15),
    Duration(seconds: 25),
    Duration(seconds: 40),
    Duration(seconds: 60),
    Duration(seconds: 90),
    Duration(seconds: 120),
  ];

  final SiteService _service;
  final CatalogModeController? _catalogModeController;
  final Random _random = Random();

  final Map<_MapCacheKey, _CatalogSnapshot> _snapshots = {
    _MapCacheKey.archive: _CatalogSnapshot(),
    _MapCacheKey.fieldLinked: _CatalogSnapshot(),
    _MapCacheKey.fieldShowAll: _CatalogSnapshot(),
  };

  SiteSummary? _selectedSite;
  Timer? _fieldPollTimer;
  int _fieldPollBackoffSeq = 0;
  SiteMapFilters _filters = SiteMapFilters();
  bool _showAllFieldSites = false;

  _MapCacheKey get _cacheKey {
    if (_dataSource == CatalogDataSource.archive) {
      return _MapCacheKey.archive;
    }
    return _showAllFieldSites
        ? _MapCacheKey.fieldShowAll
        : _MapCacheKey.fieldLinked;
  }

  _CatalogSnapshot get _snap => _snapshots[_cacheKey]!;

  _CatalogSnapshot get _activeFieldSnap => _snapshots[
      _showAllFieldSites ? _MapCacheKey.fieldShowAll : _MapCacheKey.fieldLinked]!;

  Iterable<_CatalogSnapshot> get _fieldSnaps => [
        _snapshots[_MapCacheKey.fieldLinked]!,
        _snapshots[_MapCacheKey.fieldShowAll]!,
      ];

  List<SiteSummary> get geoSites => List.unmodifiable(_snap.geoSites);

  /// Sites after applying [filters] (used for map markers).
  List<SiteSummary> get filteredGeoSites {
    if (!_filters.hasActiveFilters) {
      return geoSites;
    }
    return List.unmodifiable(
      _snap.geoSites.where(_filters.matches),
    );
  }

  SiteMapFilters get filters => _filters;

  bool get hasActiveFilters => _filters.hasActiveFilters;

  bool get showAllFieldSites => _showAllFieldSites;

  /// Toggle admin show-all without wiping the other field cache (same idea as
  /// archive ↔ field).
  void setShowAllFieldSites(bool value) {
    if (_showAllFieldSites == value) return;
    _showAllFieldSites = value;
    clearSelection();
    if (!_isFieldMode) {
      notifyListeners();
      return;
    }

    _stopFieldPoll();
    _stopFieldPollBackoff();

    final snap = _snap;
    if (snap.loadingComplete) {
      _startFieldPoll(snap.loadSeq);
      unawaited(_pollNewFieldSites(snap.loadSeq));
      notifyListeners();
      return;
    }
    if (snap.loading) {
      notifyListeners();
      return;
    }
    load(force: false);
  }

  void applyFilters(SiteMapFilters filters) {
    _filters = filters.copyWith(filterByStatus: _isFieldMode);
    notifyListeners();
  }

  bool get loading => _snap.loading;
  bool get loadingComplete => _snap.loadingComplete;
  bool get isLoadingMore => _snap.loading && _snap.geoSites.isNotEmpty;
  String? get error => _snap.error;
  SiteSummary? get selectedSite => _selectedSite;
  LatLngBounds? get siteBounds => _snap.siteBounds;
  int get totalCatalog => _snap.totalCatalog;
  int get loadedCatalog => _snap.loadedCatalog;
  int get geoSiteCount => _snap.geoSites.length;
  bool get isEmpty =>
      !_snap.loading &&
      _snap.loadingComplete &&
      _snap.error == null &&
      _snap.geoSites.isEmpty;

  CatalogDataSource get _dataSource =>
      _catalogModeController?.dataSource ?? CatalogDataSource.archive;

  bool get _isFieldMode => _dataSource == CatalogDataSource.field;

  /// Switch archive/field without wiping the other mode's cache.
  void onDataSourceChanged() {
    clearSelection();
    _stopFieldPoll();
    _stopFieldPollBackoff();
    _filters = _filters.copyWith(filterByStatus: _isFieldMode);

    final snap = _snap;
    if (snap.loadingComplete) {
      if (_isFieldMode) {
        _startFieldPoll(snap.loadSeq);
        // Pick up sites generated while user was in archive mode.
        unawaited(_pollNewFieldSites(snap.loadSeq));
      }
      notifyListeners();
      return;
    }

    if (snap.loading) {
      notifyListeners();
      return;
    }

    load(force: false);
  }

  /// Starts or resumes background site pagination without blocking the map UI.
  void load({bool force = false}) {
    if (_isFieldMode) {
      _loadFieldMode(force: force);
      return;
    }

    final snap = _snap;
    if (!force) {
      if (snap.loading || snap.loadingComplete) {
        notifyListeners();
        return;
      }
    } else {
      snap.reset(clearSeed: true);
      snap.seed = _newSeed();
    }

    snap.seed ??= _newSeed();

    final seq = ++snap.loadSeq;
    snap.loading = true;
    snap.error = null;
    notifyListeners();

    unawaited(_loadArchivePages(seq));
  }

  /// Drop field markers and reload for the newly signed-in user.
  ///
  /// Field sites are per-user (linked via ``user_site``). Keeping the previous
  /// account's markers would leak discoveries across logins.
  void onUserChanged({required bool isAdmin}) {
    clearSelection();
    _stopFieldPoll();
    _stopFieldPollBackoff();
    if (!isAdmin) {
      _showAllFieldSites = false;
    }
    for (final snap in _fieldSnaps) {
      snap.reset(clearSeed: false);
      snap.loadSeq++;
    }
    notifyListeners();
    load(force: true);
  }

  void _loadFieldMode({required bool force}) {
    final snap = _snap;
    if (!force) {
      if (snap.loading) {
        notifyListeners();
        return;
      }
      if (snap.loadingComplete) {
        _startFieldPoll(snap.loadSeq);
        notifyListeners();
        return;
      }
    } else {
      snap.reset(clearSeed: false);
    }

    _stopFieldPoll();
    final seq = ++snap.loadSeq;
    snap.loading = true;
    snap.loadingComplete = false;
    snap.error = null;
    notifyListeners();

    unawaited(_loadFieldPages(seq));
  }

  void pause() {
    for (final snap in _snapshots.values) {
      snap.loadSeq++;
      snap.loading = false;
    }
    _stopFieldPoll();
    _stopFieldPollBackoff();
    notifyListeners();
  }

  Future<void> refresh() async {
    load(force: true);
  }

  /// Poll for newly generated field sites soon after an ensure request.
  void scheduleFieldPollAfterEnsure() {
    final fieldSnap = _activeFieldSnap;
    _stopFieldPollBackoff();
    final seq = fieldSnap.loadSeq;
    _fieldPollBackoffSeq = seq;
    if (!_isFieldMode) {
      // Ensure may run while viewing archive; poll when user returns to field.
      return;
    }
    unawaited(_pollNewFieldSites(seq));
    for (final delay in _fieldPollBurstDelays) {
      Future<void>.delayed(delay, () {
        if (seq != _fieldPollBackoffSeq ||
            seq != fieldSnap.loadSeq ||
            !_isFieldMode) {
          return;
        }
        unawaited(_pollNewFieldSites(seq));
      });
    }
  }

  /// Immediate poll for new field sites (field mode only).
  Future<void> pollNow() async {
    if (!_isFieldMode) return;
    await _pollNewFieldSites(_snap.loadSeq);
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

  void upsertSite(SiteSummary site) {
    // Keep both field views in sync after discover / admin status edits.
    for (final snap in _fieldSnaps) {
      _mergeSites(snap, [site]);
    }
    if (_selectedSite?.siteId == site.siteId) {
      _selectedSite = site;
    }
    notifyListeners();
  }

  void _replaceCachedSite(SiteSummary site) {
    final snap = _snap;
    final index = snap.geoSites.indexWhere((s) => s.siteId == site.siteId);
    if (index < 0) return;
    final updated = [...snap.geoSites];
    updated[index] = site;
    snap.geoSites = updated;
    if (_selectedSite?.siteId == site.siteId) {
      _selectedSite = site;
    }
    notifyListeners();
  }

  void _mergeSites(_CatalogSnapshot snap, List<SiteSummary> incoming) {
    if (incoming.isEmpty) return;
    final byId = {for (final site in snap.geoSites) site.siteId: site};
    for (final site in incoming) {
      byId[site.siteId] = site;
    }
    snap.geoSites = byId.values.toList();
    snap.siteBounds = _expandBounds(snap.siteBounds, incoming);
    snap.maxFieldSiteId = snap.geoSites.fold(
      snap.maxFieldSiteId,
      (max, site) => site.siteId > max ? site.siteId : max,
    );
  }

  Future<void> _loadFieldPages(int seq) async {
    final snap = _snap;
    final showAll = _showAllFieldSites;
    try {
      var hasMore = true;
      var offset = 0;

      while (hasMore) {
        if (seq != snap.loadSeq) return;

        final response = await _service.fetchSites(
          limit: pageSize,
          offset: offset,
          sort: 'name',
          dataSource: CatalogDataSource.field,
          showAll: showAll,
        );
        if (seq != snap.loadSeq) return;

        final geo = _withCoordinates(response.items);
        // Full catalog load must replace, not merge — otherwise a previous
        // user's linked sites remain visible after login switch.
        if (offset == 0) {
          snap.geoSites = geo;
          snap.siteBounds = _expandBounds(null, geo);
          snap.maxFieldSiteId = geo.fold(
            0,
            (max, site) => site.siteId > max ? site.siteId : max,
          );
        } else {
          _mergeSites(snap, geo);
        }
        offset += response.items.length;
        snap.loadedCatalog = offset;
        snap.totalCatalog = response.total;
        snap.error = null;
        if (_isFieldMode && _showAllFieldSites == showAll) {
          notifyListeners();
        }

        hasMore = response.hasMore;
        if (response.items.isEmpty) {
          hasMore = false;
        }

        if (kDebugMode) {
          debugPrint(
            'MapController: field page loaded — ${snap.geoSites.length} geo sites '
            '(${snap.loadedCatalog}/${snap.totalCatalog} catalog, '
            'showAll=$showAll)',
          );
        }

        if (hasMore) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      if (seq != snap.loadSeq) return;
      snap.loadingComplete = true;
      if (_isFieldMode && _showAllFieldSites == showAll) {
        _startFieldPoll(seq);
      }

      if (kDebugMode) {
        debugPrint(
          'MapController: field catalog finished — ${snap.geoSites.length} geo sites '
          'from ${snap.loadedCatalog} catalog rows (showAll=$showAll)',
        );
      }
    } on SiteServiceException catch (error) {
      if (seq != snap.loadSeq) return;
      snap.error = error.message;
    } catch (error) {
      if (seq != snap.loadSeq) return;
      snap.error =
          'Could not reach the API at ${AppConfig.baseApiUrl}. '
          'Check your connection or try again later.';
      if (kDebugMode) {
        debugPrint('MapController.load field mode failed: $error');
      }
    } finally {
      if (seq == snap.loadSeq) {
        snap.loading = false;
        if (_isFieldMode && _showAllFieldSites == showAll) {
          notifyListeners();
        }
      }
    }
  }

  void _startFieldPoll(int seq) {
    _stopFieldPoll();
    _fieldPollTimer = Timer.periodic(fieldPollInterval, (_) {
      if (seq != _activeFieldSnap.loadSeq || !_isFieldMode) {
        return;
      }
      unawaited(_pollNewFieldSites(seq));
    });
  }

  void _stopFieldPoll() {
    _fieldPollTimer?.cancel();
    _fieldPollTimer = null;
  }

  void _stopFieldPollBackoff() {
    _fieldPollBackoffSeq++;
  }

  Future<void> _pollNewFieldSites(int seq) async {
    final snap = _activeFieldSnap;
    final showAll = _showAllFieldSites;
    if (seq != snap.loadSeq) return;

    try {
      var hasMore = true;
      var siteIdMin = snap.maxFieldSiteId > 0 ? snap.maxFieldSiteId + 1 : null;

      while (hasMore) {
        if (seq != snap.loadSeq) return;

        final response = await _service.fetchSites(
          limit: pageSize,
          offset: 0,
          sort: 'name',
          dataSource: CatalogDataSource.field,
          siteIdMin: siteIdMin,
          showAll: showAll,
        );
        if (seq != snap.loadSeq) return;
        if (response.items.isEmpty) return;

        final geo = _withCoordinates(response.items);
        _mergeSites(snap, geo);
        snap.totalCatalog = response.total;
        if (_isFieldMode && _showAllFieldSites == showAll) {
          notifyListeners();
        }

        hasMore = response.hasMore;
        if (hasMore) {
          siteIdMin = snap.maxFieldSiteId + 1;
        }

        if (kDebugMode) {
          debugPrint(
            'MapController: polled ${geo.length} new field sites '
            '(max id ${snap.maxFieldSiteId}, showAll=$showAll)',
          );
        }
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('MapController field poll failed: $error');
      }
    }
  }

  Future<void> _loadArchivePages(int seq) async {
    final snap = _snapshots[_MapCacheKey.archive]!;
    try {
      var hasMore = true;

      while (hasMore) {
        if (seq != snap.loadSeq) return;

        final response = await _fetchArchivePage(snap: snap, offset: snap.offset);
        if (seq != snap.loadSeq) return;

        final geo = _withCoordinates(response.items);

        snap.geoSites = [...snap.geoSites, ...geo];
        snap.offset += response.items.length;
        snap.loadedCatalog = snap.offset;
        snap.totalCatalog = response.total;
        snap.siteBounds = _expandBounds(snap.siteBounds, geo);
        snap.error = null;
        if (!_isFieldMode) {
          notifyListeners();
        }

        hasMore = response.hasMore;
        if (response.items.isEmpty) {
          hasMore = false;
        }

        if (kDebugMode) {
          debugPrint(
            'MapController: page loaded — ${snap.geoSites.length} geo sites '
            '(${snap.loadedCatalog}/${snap.totalCatalog} catalog)',
          );
        }

        if (hasMore) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      if (seq != snap.loadSeq) return;
      snap.loadingComplete = true;

      if (kDebugMode) {
        debugPrint(
          'MapController: finished — ${snap.geoSites.length} geo sites '
          'from ${snap.loadedCatalog} catalog rows',
        );
      }
    } on SiteServiceException catch (error) {
      if (seq != snap.loadSeq) return;
      snap.error = error.message;
    } catch (error) {
      if (seq != snap.loadSeq) return;
      snap.error =
          'Could not reach the API at ${AppConfig.baseApiUrl}. '
          'Check your connection or try again later.';
      if (kDebugMode) {
        debugPrint('MapController.load failed: $error');
      }
    } finally {
      if (seq == snap.loadSeq) {
        snap.loading = false;
        if (!_isFieldMode) {
          notifyListeners();
        }
      }
    }
  }

  Future<SiteListResponse> _fetchArchivePage({
    required _CatalogSnapshot snap,
    required int offset,
  }) async {
    final seed = snap.seed;
    if (seed == null || seed.isEmpty) {
      throw StateError('Map catalog seed missing before fetch');
    }
    return _service.fetchSites(
      limit: pageSize,
      offset: offset,
      sort: 'random',
      seed: seed,
      dataSource: CatalogDataSource.archive,
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
    for (final snap in _snapshots.values) {
      snap.loadSeq++;
    }
    _stopFieldPoll();
    _service.dispose();
    super.dispose();
  }
}
