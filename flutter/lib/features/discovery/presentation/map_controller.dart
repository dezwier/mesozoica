import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../config/app_config.dart';
import '../../../config/map_config.dart';
import '../../../controllers/catalog_mode_controller.dart';
import '../../../models/site.dart';
import '../../../models/site_map_filters.dart';
import '../data/site_repository.dart';
import 'map_catalog_cache.dart';
import 'map_filter_state.dart';
import 'map_polling_coordinator.dart';
import 'map_selection_state.dart';
import 'map_viewport_loader.dart';

export 'map_viewport_loader.dart' show ShowAllLoadResult;

class MapController extends ChangeNotifier {
  MapController({
    SiteService? service,
    CatalogModeController? catalogModeController,
  }) : _service = service ?? SiteService(),
       _catalogModeController = catalogModeController {
    _viewportLoader = MapViewportLoader(
      service: _service,
      snapshot: () => _snapshots[MapCacheKey.fieldShowAll]!,
      isFieldMode: () => _isFieldMode,
      isEnabled: () => _showAllFieldSites,
      withCoordinates: _withCoordinates,
      expandBounds: _expandBounds,
      notifyChanged: _notifyChanged,
    );
  }

  static const pageSize = 500;
  static const fieldPollInterval = Duration(seconds: 60);

  /// Archive catalog changes about weekly; soft-refresh without blanking toggles.
  static const archiveCacheTtl = Duration(days: 7);

  final SiteService _service;
  final CatalogModeController? _catalogModeController;
  final Random _random = Random();
  late final MapViewportLoader _viewportLoader;

  // Part files are library helpers rather than ChangeNotifier subclasses, so
  // they notify through this owner method instead of calling the protected
  // framework member directly.
  void _notifyChanged() => notifyListeners();

  final Map<MapCacheKey, MapCatalogSnapshot> _snapshots = {
    MapCacheKey.archive: MapCatalogSnapshot(),
    MapCacheKey.fieldLinked: MapCatalogSnapshot(),
    MapCacheKey.fieldShowAll: MapCatalogSnapshot(),
  };
  final MapSelectionState _selection = MapSelectionState();
  final MapPollingCoordinator _polling = MapPollingCoordinator();
  final MapFilterState _filterState = MapFilterState();
  bool _showAllFieldSites = false;

  /// Bumped when a soft archive reload replaces the list (force marker rebuild).
  int _archiveEpoch = 0;

  MapCacheKey get _cacheKey {
    if (_dataSource == CatalogDataSource.archive) {
      return MapCacheKey.archive;
    }
    return _showAllFieldSites
        ? MapCacheKey.fieldShowAll
        : MapCacheKey.fieldLinked;
  }

  MapCatalogSnapshot get _snap => _snapshots[_cacheKey]!;

  MapCatalogSnapshot get _activeFieldSnap =>
      _snapshots[_showAllFieldSites
          ? MapCacheKey.fieldShowAll
          : MapCacheKey.fieldLinked]!;

  Iterable<MapCatalogSnapshot> get _fieldSnaps => [
    _snapshots[MapCacheKey.fieldLinked]!,
    _snapshots[MapCacheKey.fieldShowAll]!,
  ];

  List<SiteSummary> get geoSites => List.unmodifiable(_snap.geoSites);

  /// Sites to paint on the map.
  ///
  /// Show-all only paints the show-all snapshot after a real `show_all` API
  /// load. Until then (or on failure) it keeps the
  /// linked markers visible without copying them into the show-all cache.
  List<SiteSummary> get filteredGeoSites {
    if (_showAllFieldSites && _isFieldMode) {
      final showAll = _snapshots[MapCacheKey.fieldShowAll]!;
      if (_viewportLoader.authoritative) {
        return List.unmodifiable(showAll.geoSites);
      }
      final linked = _snapshots[MapCacheKey.fieldLinked]!;
      if (!_filterState.hasActiveFilters) {
        return List.unmodifiable(linked.geoSites);
      }
      return _filterState.filter(linked.geoSites);
    }
    return _filterState.filter(_snap.geoSites);
  }

  /// Marker dataset key — stay on `field:linked` until show-all API data lands.
  String mapMarkerDatasetKey({required bool isFieldMode}) {
    if (!isFieldMode) {
      return 'archive:$archiveEpoch|${_filterState.markerKey}';
    }
    if (_showAllFieldSites && _viewportLoader.authoritative) {
      return 'field:all|all';
    }
    return 'field:linked|${_filterState.markerKey}';
  }

  SiteMapFilters get filters => _filterState.value;

  bool get hasActiveFilters => _filterState.hasActiveFilters;

  bool get showAllFieldSites => _showAllFieldSites;

  /// Included in the map marker dataset key after archive soft-refresh replace.
  int get archiveEpoch => _archiveEpoch;

  /// Toggle on-demand admin "sites in view" without wiping the linked field
  /// cache. Enabling clears the show-all snapshot; the screen then loads the
  /// current viewport via [loadShowAllInBounds]. Disabling returns to
  /// discovered/linked markers only.
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

    if (value) {
      // Clean slate every enable: never paint stale/polluted show-all data.
      _viewportLoader.reset();
      final showAll = _snapshots[MapCacheKey.fieldShowAll]!;
      ++showAll.loadSeq;
      showAll.geoSites = [];
      showAll.siteBounds = null;
      showAll.loadedCatalog = 0;
      showAll.totalCatalog = 0;
      showAll.maxFieldSiteId = 0;
      showAll.loadingComplete = false;
      showAll.loading = false;
      showAll.error = null;
      // Keep linked markers (and any in-flight linked load). Show-all paints
      // linked until authoritative; aborting linked here blanked the map when
      // show-all timed out against a busy API.
      notifyListeners();
      return;
    }

    // Back to linked — keep show-all snap empty for the next enable.
    _viewportLoader.reset();
    final showAll = _snapshots[MapCacheKey.fieldShowAll]!;
    ++showAll.loadSeq; // abort any in-flight show-all HTTP pages
    showAll.geoSites = [];
    showAll.loadingComplete = false;
    showAll.loading = false;
    showAll.error = null;

    final snap = _snap;
    // After a failed/cancelled show-all, linked may be empty/incomplete — reload.
    if (snap.geoSites.isEmpty || !snap.loadingComplete) {
      load(force: true);
      return;
    }
    _startFieldPoll(snap.loadSeq);
    notifyListeners();
  }

  /// On-demand admin show-all: replace markers with every field site inside
  /// [bounds] (≤ [MapConfig.showAllMaxSites]). Paginate until complete, then
  /// replace atomically. At most one show-all HTTP chain runs at a time;
  /// newer bounds coalesce as pending.
  Future<ShowAllLoadResult> loadShowAllInBounds(
    LatLngBounds bounds, {
    bool force = false,
  }) {
    _stopFieldPoll();
    return _viewportLoader.load(bounds, force: force);
  }

  void applyFilters(SiteMapFilters filters) {
    _filterState.apply(filters, isFieldMode: _isFieldMode);
    notifyListeners();
  }

  bool get loading => _snap.loading;
  bool get loadingComplete => _snap.loadingComplete;
  bool get isLoadingMore => _snap.loading && _snap.geoSites.isNotEmpty;
  String? get error => _snap.error;
  SiteSummary? get selectedSite => _selection.selectedSite;
  SiteSummary? get pendingFocusSite => _selection.pendingFocusSite;
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
    _filterState.updateMode(isFieldMode: _isFieldMode);

    final snap = _snap;
    if (snap.loadingComplete) {
      if (_isFieldMode) {
        _startFieldPoll(snap.loadSeq);
        // Pick up sites generated while user was in archive mode.
        unawaited(_pollNewFieldSites(snap.loadSeq));
      } else if (_archiveIsStale) {
        notifyListeners();
        _softRefreshArchive();
        return;
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

  bool get _archiveIsStale {
    final loadedAt = _snapshots[MapCacheKey.archive]!.loadedAt;
    if (loadedAt == null) return true;
    return DateTime.now().difference(loadedAt) >= archiveCacheTtl;
  }

  /// Reload archive in the background without blanking markers on toggle.
  void _softRefreshArchive() {
    final snap = _snapshots[MapCacheKey.archive]!;
    if (snap.loading) return;
    snap.seed = _newSeed();
    snap.offset = 0;
    snap.loadedCatalog = 0;
    snap.totalCatalog = 0;
    snap.error = null;
    snap.replaceOnNextPage = true;
    snap.loadedAt = null;
    final seq = ++snap.loadSeq;
    snap.loading = true;
    snap.loadingComplete = false;
    unawaited(_loadArchivePages(seq));
  }

  /// Starts or resumes background site pagination without blocking the map UI.
  void load({bool force = false}) {
    if (_isFieldMode) {
      if (_showAllFieldSites) {
        final bounds = _viewportLoader.bounds;
        if (bounds != null) {
          loadShowAllInBounds(bounds, force: force);
        } else {
          notifyListeners();
        }
        return;
      }
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
    _viewportLoader.reset();
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
      // Keep existing markers visible until the first page arrives so rapid
      // discovery refreshes (aerial recon) don't blank the map.
      snap.offset = 0;
      snap.loadedCatalog = 0;
      snap.totalCatalog = 0;
      snap.error = null;
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
    if (!_isFieldMode) {
      // Ensure may run while viewing archive; poll when user returns to field.
      return;
    }
    // Show-all ignores linked polling — burst-reload the viewport so sites
    // written by the ensure worker appear without a manual pan/re-toggle.
    if (_showAllFieldSites) {
      Future<void> reloadShowAll() async {
        final bounds = _viewportLoader.bounds ?? _viewportLoader.pendingBounds;
        if (bounds == null) return;
        await loadShowAllInBounds(bounds, force: true);
      }

      _polling.scheduleBurst(
        isValid: () =>
            seq == fieldSnap.loadSeq && _isFieldMode && _showAllFieldSites,
        poll: reloadShowAll,
      );
      return;
    }
    _polling.scheduleBurst(
      isValid: () => seq == fieldSnap.loadSeq && _isFieldMode,
      poll: () => _pollNewFieldSites(seq),
    );
  }

  /// Immediate poll for new field sites (field mode only).
  Future<void> pollNow() async {
    if (!_isFieldMode) return;
    await _pollNewFieldSites(_snap.loadSeq);
  }

  void selectSite(SiteSummary site) {
    _selection.select(site);
    notifyListeners();
  }

  void clearSelection() {
    if (!_selection.clear()) return;
    notifyListeners();
  }

  /// Select [site] and queue a camera pan when the map screen is ready.
  void requestFocusOnSite(SiteSummary site) {
    _selection.select(site, requestFocus: true);
    notifyListeners();
  }

  /// Returns and clears a pending focus request, if any.
  SiteSummary? takePendingFocusSite() {
    return _selection.takePendingFocusSite();
  }

  /// Loads the latest site row so formation and other card fields are current.
  Future<SiteSummary> siteForDisplay(
    SiteSummary site, {
    bool includeExactOdds = false,
  }) async {
    try {
      final fresh = await _service.fetchSiteById(
        site.siteId,
        dataSource: _dataSource,
        includeExactOdds: includeExactOdds,
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
    _selection.replaceIfSelected(site);
    notifyListeners();
  }

  void _replaceCachedSite(SiteSummary site) {
    final snap = _snap;
    final index = snap.geoSites.indexWhere((s) => s.siteId == site.siteId);
    if (index < 0) return;
    final updated = [...snap.geoSites];
    updated[index] = site;
    snap.geoSites = updated;
    _selection.replaceIfSelected(site);
    notifyListeners();
  }

  void _mergeSites(MapCatalogSnapshot snap, List<SiteSummary> incoming) {
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
    // Linked field catalog only — show-all uses [_loadShowAllPages].
    const showAll = false;
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
        if (_isFieldMode && !_showAllFieldSites) {
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
      snap.loadedAt = DateTime.now();
      if (_isFieldMode && !_showAllFieldSites) {
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
        if (_isFieldMode && !_showAllFieldSites) {
          notifyListeners();
        }
      }
    }
  }

  void _startFieldPoll(int seq) {
    _polling.startPeriodic(
      interval: fieldPollInterval,
      isValid: () => seq == _activeFieldSnap.loadSeq && _isFieldMode,
      poll: () => _pollNewFieldSites(seq),
    );
  }

  void _stopFieldPoll() => _polling.stopPeriodic();

  void _stopFieldPollBackoff() => _polling.stopBurst();

  Future<void> _pollNewFieldSites(int seq) async {
    final snap = _activeFieldSnap;
    if (seq != snap.loadSeq) return;

    // Show-all is on-demand only — never auto-refresh while it is active.
    if (_showAllFieldSites) return;

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
          showAll: false,
        );
        if (seq != snap.loadSeq) return;
        if (response.items.isEmpty) return;

        final geo = _withCoordinates(response.items);
        _mergeSites(snap, geo);
        snap.totalCatalog = response.total;
        if (_isFieldMode && !_showAllFieldSites) {
          notifyListeners();
        }

        hasMore = response.hasMore;
        if (hasMore) {
          siteIdMin = snap.maxFieldSiteId + 1;
        }

        if (kDebugMode) {
          debugPrint(
            'MapController: polled ${geo.length} new field sites '
            '(max id ${snap.maxFieldSiteId})',
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
    final snap = _snapshots[MapCacheKey.archive]!;
    try {
      var hasMore = true;

      while (hasMore) {
        if (seq != snap.loadSeq) return;

        final response = await _fetchArchivePage(
          snap: snap,
          offset: snap.offset,
        );
        if (seq != snap.loadSeq) return;

        final geo = _withCoordinates(response.items);

        if (snap.offset == 0 && snap.replaceOnNextPage) {
          snap.geoSites = geo;
          snap.siteBounds = _expandBounds(null, geo);
          snap.replaceOnNextPage = false;
          // Force marker wipe+rebuild; append-only sync cannot drop removed ids.
          _archiveEpoch++;
        } else {
          snap.geoSites = [...snap.geoSites, ...geo];
          snap.siteBounds = _expandBounds(snap.siteBounds, geo);
        }
        snap.offset += response.items.length;
        snap.loadedCatalog = snap.offset;
        snap.totalCatalog = response.total;
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
      snap.loadedAt = DateTime.now();

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
    required MapCatalogSnapshot snap,
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
        .where((site) => site.latitude != null && site.longitude != null)
        .toList();
  }

  LatLngBounds? _expandBounds(LatLngBounds? existing, List<SiteSummary> sites) {
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

    return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  @override
  void dispose() {
    for (final snap in _snapshots.values) {
      snap.loadSeq++;
    }
    _polling.dispose();
    _service.dispose();
    super.dispose();
  }
}
