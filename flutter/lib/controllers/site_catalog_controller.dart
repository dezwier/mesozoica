import 'dart:math';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/site.dart';
import '../services/site_service.dart';
import '../widgets/cards/site_card_image.dart';

class SiteCatalogController extends ChangeNotifier {
  SiteCatalogController({SiteService? service})
      : _service = service ?? SiteService();

  static const pageSize = 20;
  static const _clientScanPageSize = 500;

  final SiteService _service;
  final Random _random = Random();

  List<SiteSummary> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  String? _seed;
  int _loadSeq = 0;
  int _offset = 0;
  bool _hasMore = false;
  int _total = 0;
  bool _useClientCustomImageFilter = false;

  List<SiteSummary> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  bool get isLoadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  bool get isEmpty => !_loading && _error == null && _items.isEmpty;
  int get total => _total;

  Future<void> load({bool force = false}) async {
    if (!force && _items.isNotEmpty) return;

    final seq = ++_loadSeq;
    final keepExistingItems = force && _items.isNotEmpty;

    _loading = true;
    _error = null;
    _useClientCustomImageFilter = false;
    _seed = _newSeed();
    _offset = 0;
    _hasMore = false;
    if (!keepExistingItems) {
      _items = [];
      _total = 0;
    }
    notifyListeners();

    try {
      final response = await _fetchPage(offset: 0);
      if (seq != _loadSeq) return;
      _items = response.items;
      _offset = response.items.length;
      _hasMore = response.hasMore;
      _total = response.total;
      _error = null;
    } on SiteServiceException catch (error) {
      if (seq != _loadSeq) return;
      _error = error.message;
    } catch (error) {
      if (seq != _loadSeq) return;
      _error =
          'Could not reach the API at ${AppConfig.baseApiUrl}. '
          'Check your connection or try again later.';
      if (kDebugMode) {
        debugPrint('SiteCatalogController.load failed: $error');
      }
    } finally {
      if (seq == _loadSeq) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _useClientCustomImageFilter) {
      return;
    }
    if (_seed == null) return;

    _loadingMore = true;
    notifyListeners();

    try {
      final response = await _fetchPage(offset: _offset);
      _items = [..._items, ...response.items];
      _offset += response.items.length;
      _hasMore = response.hasMore;
      _total = response.total;
      _error = null;
    } on SiteServiceException catch (error) {
      _error = error.message;
    } catch (error) {
      _error =
          'Could not reach the API at ${AppConfig.baseApiUrl}. '
          'Check your connection or try again later.';
      if (kDebugMode) {
        debugPrint('SiteCatalogController.loadMore failed: $error');
      }
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load(force: true);

  Future<SiteListResponse> _fetchPage({required int offset}) async {
    if (_useClientCustomImageFilter) {
      return _fetchAllCuratedClientSide();
    }

    final seed = _seed;
    if (seed == null || seed.isEmpty) {
      throw StateError('Catalog seed missing before fetch');
    }
    final response = await _service.fetchSites(
      limit: pageSize,
      offset: offset,
      sort: 'random',
      seed: seed,
      hasCustomImage: true,
    );

    if (offset == 0 && !_serverHonorsCustomImageFilter(response)) {
      _useClientCustomImageFilter = true;
      if (kDebugMode) {
        debugPrint(
          'SiteCatalogController: API ignored has_custom_image; '
          'scanning catalog client-side',
        );
      }
      return _fetchAllCuratedClientSide();
    }

    return response;
  }

  bool _serverHonorsCustomImageFilter(SiteListResponse response) {
    return !response.items.any(
      (site) => !SiteCardImage.isCuratedCardImageUrl(site.mainImageUrl),
    );
  }

  Future<SiteListResponse> _fetchAllCuratedClientSide() async {
    final curated = <SiteSummary>[];
    var offset = 0;
    var hasMore = true;

    while (hasMore) {
      final response = await _service.fetchSites(
        limit: _clientScanPageSize,
        offset: offset,
        sort: 'name',
      );
      curated.addAll(
        response.items.where(
          (site) => SiteCardImage.isCuratedCardImageUrl(site.mainImageUrl),
        ),
      );
      offset += response.items.length;
      hasMore = response.hasMore;
      if (response.items.isEmpty) break;
    }

    if (curated.length > 1) {
      curated.shuffle(_random);
    }

    return SiteListResponse(
      items: curated,
      total: curated.length,
      limit: curated.length,
      offset: 0,
      hasNext: false,
    );
  }

  String _newSeed() {
    return '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
