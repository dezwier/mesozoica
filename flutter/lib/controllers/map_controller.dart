import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../controllers/fossil_catalog_controller.dart';
import '../models/fossil.dart';
import '../services/fossil_service.dart';
import '../widgets/cards/dinosaur_card_image.dart';

class MapController extends ChangeNotifier {
  MapController({FossilService? service})
      : _service = service ?? FossilService();

  static const pageSize = 500;
  static const _clientScanPageSize = 500;

  final FossilService _service;

  List<FossilSummary> _geoFossils = [];
  bool _loading = false;
  bool _loadingComplete = false;
  String? _error;
  FossilSummary? _selectedFossil;
  LatLngBounds? _fossilBounds;
  int _loadSeq = 0;
  int _offset = 0;
  int _totalCatalog = 0;
  int _loadedCatalog = 0;
  FossilCatalogFilters _filters = FossilCatalogFilters.defaults;
  bool _useClientCustomImageFilter = false;

  List<FossilSummary> get geoFossils => List.unmodifiable(_geoFossils);
  bool get loading => _loading;
  bool get loadingComplete => _loadingComplete;
  bool get isLoadingMore => _loading && _geoFossils.isNotEmpty;
  String? get error => _error;
  FossilSummary? get selectedFossil => _selectedFossil;
  LatLngBounds? get fossilBounds => _fossilBounds;
  int get totalCatalog => _totalCatalog;
  int get loadedCatalog => _loadedCatalog;
  int get geoFossilCount => _geoFossils.length;
  FossilCatalogFilters get filters => _filters;
  bool get hasActiveFilters => _filters.hasActiveFilters;
  bool get isEmpty =>
      !_loading && _loadingComplete && _error == null && _geoFossils.isEmpty;

  /// Starts or resumes background fossil pagination without blocking the map UI.
  void load({bool force = false}) {
    if (!force) {
      if (_loading || _loadingComplete) return;
    } else {
      _geoFossils = [];
      _fossilBounds = null;
      _offset = 0;
      _loadedCatalog = 0;
      _totalCatalog = 0;
      _loadingComplete = false;
      _useClientCustomImageFilter = false;
    }

    final seq = ++_loadSeq;
    _loading = true;
    _error = null;
    notifyListeners();

    unawaited(_loadPages(seq));
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

  Future<void> applyFilters(FossilCatalogFilters filters) async {
    _filters = filters;
    load(force: true);
  }

  void selectFossil(FossilSummary fossil) {
    _selectedFossil = fossil;
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedFossil == null) return;
    _selectedFossil = null;
    notifyListeners();
  }

  Future<void> _loadPages(int seq) async {
    try {
      if (_filters.onlyCustomImage && _useClientCustomImageFilter) {
        final response = await _fetchAllCuratedClientSide();
        if (seq != _loadSeq) return;

        final geo = _withCoordinates(response.items);
        _geoFossils = geo;
        _offset = response.items.length;
        _loadedCatalog = response.total;
        _totalCatalog = response.total;
        _fossilBounds = _expandBounds(null, geo);
        _loadingComplete = true;
        _error = null;
        notifyListeners();
        return;
      }

      var hasMore = true;

      while (hasMore) {
        if (seq != _loadSeq) return;

        final response = await _fetchPage(offset: _offset);
        if (seq != _loadSeq) return;

        final geo = _withCoordinates(response.items);

        _geoFossils = [..._geoFossils, ...geo];
        _offset += response.items.length;
        _loadedCatalog = _offset;
        _totalCatalog = response.total;
        _fossilBounds = _expandBounds(_fossilBounds, geo);
        _error = null;
        notifyListeners();

        hasMore = response.hasMore;
        if (response.items.isEmpty) {
          hasMore = false;
        }

        if (kDebugMode) {
          debugPrint(
            'MapController: page loaded — ${_geoFossils.length} geo fossils '
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
          'MapController: finished — ${_geoFossils.length} geo fossils '
          'from $_loadedCatalog catalog rows',
        );
      }
    } on FossilServiceException catch (error) {
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

  Future<FossilListResponse> _fetchPage({required int offset}) async {
    if (_filters.onlyCustomImage && _useClientCustomImageFilter) {
      return _fetchAllCuratedClientSide();
    }

    final hasSearch = _filters.searchQuery.trim().isNotEmpty;
    final response = await _service.fetchFossils(
      limit: pageSize,
      offset: offset,
      sort: 'name',
      q: hasSearch ? _filters.searchQuery.trim() : null,
      maYounger:
          !hasSearch && _filters.hasTimeFilter ? _filters.maYounger : null,
      maOlder: !hasSearch && _filters.hasTimeFilter ? _filters.maOlder : null,
      hasCustomImage: _filters.onlyCustomImage,
    );

    if (_filters.onlyCustomImage &&
        offset == 0 &&
        !_serverHonorsCustomImageFilter(response)) {
      _useClientCustomImageFilter = true;
      if (kDebugMode) {
        debugPrint(
          'MapController: API ignored has_custom_image; '
          'scanning catalog client-side',
        );
      }
      return _fetchAllCuratedClientSide();
    }

    return response;
  }

  bool _serverHonorsCustomImageFilter(FossilListResponse response) {
    return !response.items.any(
      (fossil) =>
          !DinosaurCardImage.isCuratedCardImageUrl(fossil.dinosaurMainImageUrl),
    );
  }

  Future<FossilListResponse> _fetchAllCuratedClientSide() async {
    final hasSearch = _filters.searchQuery.trim().isNotEmpty;
    final curated = <FossilSummary>[];
    var offset = 0;
    var hasMore = true;

    while (hasMore) {
      final response = await _service.fetchFossils(
        limit: _clientScanPageSize,
        offset: offset,
        sort: 'name',
        q: hasSearch ? _filters.searchQuery.trim() : null,
        maYounger:
            !hasSearch && _filters.hasTimeFilter ? _filters.maYounger : null,
        maOlder: !hasSearch && _filters.hasTimeFilter ? _filters.maOlder : null,
      );
      curated.addAll(
        response.items.where(
          (fossil) => DinosaurCardImage.isCuratedCardImageUrl(
            fossil.dinosaurMainImageUrl,
          ),
        ),
      );
      offset += response.items.length;
      hasMore = response.hasMore;
      if (response.items.isEmpty) break;
    }

    return FossilListResponse(
      items: curated,
      total: curated.length,
      limit: curated.length,
      offset: 0,
      hasNext: false,
    );
  }

  List<FossilSummary> _withCoordinates(List<FossilSummary> fossils) {
    return fossils
        .where(
          (fossil) => fossil.latitude != null && fossil.longitude != null,
        )
        .toList();
  }

  LatLngBounds? _expandBounds(
    LatLngBounds? existing,
    List<FossilSummary> fossils,
  ) {
    if (fossils.isEmpty) return existing;

    var minLat = existing?.southWest.latitude ?? fossils.first.latitude!;
    var maxLat = existing?.northEast.latitude ?? fossils.first.latitude!;
    var minLng = existing?.southWest.longitude ?? fossils.first.longitude!;
    var maxLng = existing?.northEast.longitude ?? fossils.first.longitude!;

    for (final fossil in fossils) {
      final lat = fossil.latitude!;
      final lng = fossil.longitude!;
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

