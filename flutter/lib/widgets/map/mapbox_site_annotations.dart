import 'dart:async';

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../config/map_config.dart';
import '../../models/site.dart';
import 'mapbox_marker_images.dart';
import 'period_marker_color.dart';

/// How many circle annotations to create per native batch.
const int mapboxMarkerBatchSize = 500;

/// Syncs site markers onto Mapbox circles.
///
/// Contract:
/// - Mode/filter switch → one [deleteAll], then [createMulti] in batches of
///   [mapboxMarkerBatchSize].
/// - Same dataset (pan/zoom/scan/poll) → create missing first, then prune
///   extras (never blank the map).
/// - Rotate mode only hides circles (opacity 0); sync keeps them warm so
///   exiting to north-fixed is instant.
class MapboxSiteAnnotations {
  MapboxSiteAnnotations({
    required this.onSiteTap,
  });

  ValueChangedSite onSiteTap;

  /// Created first so it paints under the colored fill knobs.
  CircleAnnotationManager? _shadowManager;
  CircleAnnotationManager? _manager;
  /// Created last so the selection knob paints on top of fills.
  CircleAnnotationManager? _dotManager;
  Cancelable? _tapCancelable;
  int _selectionAnimToken = 0;
  final Map<String, SiteSummary> _byAnnotationId = {};
  final Map<int, CircleAnnotation> _bySiteId = {};
  final Map<int, CircleAnnotation> _shadowBySiteId = {};
  CircleAnnotation? _selectionDot;
  int? _selectedSiteId;
  /// Bumped only on wipe ([beginDatasetSwitch] / [clearAllMarkers]) so an
  /// in-flight create/prune can abort cleanly without page-notify races.
  int _syncSeq = 0;
  String? _loadedDatasetKey;
  double _baseRadius = 8.0;
  double? _pendingZoomRadius;
  bool _radiusInFlight = false;
  bool _rotateModePaused = false;

  bool _syncInFlight = false;
  bool _syncDirty = false;
  MapboxMap? _latestMap;
  List<SiteSummary> _latestSites = const [];
  SiteSummary? _latestSelectedSite;
  String? _latestDatasetKey;

  /// When true, circle opacity is 0 (rotate overlay owns the UI). Sync still
  /// runs so north-fixed exit does not cold-create thousands of markers.
  bool get rotateModePaused => _rotateModePaused;

  Future<void> setRotateModePaused(bool paused) async {
    if (_rotateModePaused == paused) return;
    _rotateModePaused = paused;
    final shadowManager = _shadowManager;
    final manager = _manager;
    final dotManager = _dotManager;
    if (shadowManager == null || manager == null || dotManager == null) {
      return;
    }
    if (paused) {
      await Future.wait([
        shadowManager.setCircleOpacity(0),
        manager.setCircleOpacity(0),
        dotManager.setCircleOpacity(0),
      ]);
    } else {
      await Future.wait([
        shadowManager.setCircleOpacity(mapboxMarkerShadowOpacity),
        manager.setCircleOpacity(0.95),
        dotManager.setCircleOpacity(1.0),
      ]);
    }
  }

  Future<void> clearAllMarkers() async {
    final shadowManager = _shadowManager;
    final manager = _manager;
    final dotManager = _dotManager;
    if (shadowManager == null || manager == null || dotManager == null) {
      return;
    }
    _syncSeq++;
    _selectionAnimToken++;
    await Future.wait([
      shadowManager.deleteAll(),
      manager.deleteAll(),
      dotManager.deleteAll(),
    ]);
    _bySiteId.clear();
    _shadowBySiteId.clear();
    _byAnnotationId.clear();
    _selectionDot = null;
    _loadedDatasetKey = null;
    _selectedSiteId = null;
  }

  /// Wipe markers immediately for a dataset/filter switch.
  ///
  /// Call from the map widget as soon as [datasetKey] changes so the map
  /// blanks without waiting on debounce or camera. A following [sync] then
  /// fills in batches of [mapboxMarkerBatchSize].
  Future<void> beginDatasetSwitch(String datasetKey) async {
    if (_loadedDatasetKey == datasetKey) return;

    final shadowManager = _shadowManager;
    final manager = _manager;
    final dotManager = _dotManager;
    if (shadowManager == null || manager == null || dotManager == null) {
      return;
    }

    final seq = ++_syncSeq;
    _selectionAnimToken++;
    await Future.wait([
      shadowManager.deleteAll(),
      manager.deleteAll(),
      dotManager.deleteAll(),
    ]);
    if (seq != _syncSeq) return;
    _bySiteId.clear();
    _shadowBySiteId.clear();
    _byAnnotationId.clear();
    _selectionDot = null;
    _selectedSiteId = null;
    _loadedDatasetKey = datasetKey;
  }

  Future<void> attach({
    required CircleAnnotationManager shadowManager,
    required CircleAnnotationManager manager,
    required CircleAnnotationManager selectionDotManager,
  }) async {
    _tapCancelable?.cancel();
    _shadowManager = shadowManager;
    _manager = manager;
    _dotManager = selectionDotManager;

    await shadowManager.setCirclePitchAlignment(CirclePitchAlignment.MAP);
    await shadowManager.setCirclePitchScale(CirclePitchScale.MAP);
    await shadowManager.setCircleColor(0xFF000000);
    await shadowManager.setCircleOpacity(
      _rotateModePaused ? 0 : mapboxMarkerShadowOpacity,
    );
    await shadowManager.setCircleBlur(mapboxMarkerShadowBlur);
    await shadowManager.setCircleStrokeWidth(0);
    await shadowManager.setCircleEmissiveStrength(1.0);
    await shadowManager.setCircleRadius(
      _baseRadius * mapboxMarkerShadowRadiusScale,
    );

    await manager.setCirclePitchAlignment(CirclePitchAlignment.MAP);
    await manager.setCirclePitchScale(CirclePitchScale.MAP);
    await manager.setCircleStrokeWidth(1.5);
    await manager.setCircleStrokeColor(0xFFFFFFFF);
    await manager.setCircleOpacity(_rotateModePaused ? 0 : 0.95);
    // Keep period colors fully lit under dusk lightPreset (same as day).
    await manager.setCircleEmissiveStrength(1.0);
    await manager.setCircleRadius(_baseRadius);

    await selectionDotManager.setCirclePitchAlignment(
      CirclePitchAlignment.MAP,
    );
    await selectionDotManager.setCirclePitchScale(CirclePitchScale.MAP);
    await selectionDotManager.setCircleColor(0xFFFFFFFF);
    await selectionDotManager.setCircleOpacity(_rotateModePaused ? 0 : 1.0);
    await selectionDotManager.setCircleStrokeWidth(0);
    await selectionDotManager.setCircleEmissiveStrength(1.0);
    await selectionDotManager.setCircleRadius(_dotRadius);

    _tapCancelable = manager.tapEvents(onTap: _handleTap);
  }

  double get _shadowRadius => _baseRadius * mapboxMarkerShadowRadiusScale;

  double get _dotRadius => _baseRadius * mapboxMarkerSelectionDotScale;

  void _handleTap(CircleAnnotation annotation) {
    if (_rotateModePaused) return;
    final site = _resolveSite(annotation);
    if (site == null) return;
    // Snap selection without awaiting so the card opens with no delay.
    unawaited(applySelectedSiteId(site.siteId));
    onSiteTap(site);
  }

  /// Apply selection immediately (tap / rebuild). No-op if already selected.
  Future<void> applySelectedSiteId(int? siteId) async {
    if (_rotateModePaused) return;
    if (siteId == _selectedSiteId) return;
    final fromId = _selectedSiteId;
    _selectedSiteId = siteId;
    await _snapSelection(fromId: fromId, toId: siteId);
  }

  SiteSummary? _resolveSite(CircleAnnotation annotation) {
    final byId = _byAnnotationId[annotation.id];
    if (byId != null) return byId;

    final fromData = _siteIdFromCustomData(annotation.customData);
    if (fromData != null) {
      for (final site in _byAnnotationId.values) {
        if (site.siteId == fromData) return site;
      }
    }
    return null;
  }

  /// Coalesced sync: overlapping calls keep the latest sites and run once more
  /// after the current pass finishes (no mid-prune cancel from page notifies).
  Future<void> sync({
    required MapboxMap map,
    required List<SiteSummary> sites,
    required SiteSummary? selectedSite,
    required String datasetKey,
  }) async {
    _latestMap = map;
    _latestSites = sites;
    _latestSelectedSite = selectedSite;
    _latestDatasetKey = datasetKey;
    _syncDirty = true;
    if (_syncInFlight) return;
    _syncInFlight = true;
    try {
      while (_syncDirty) {
        _syncDirty = false;
        final runMap = _latestMap;
        final runKey = _latestDatasetKey;
        if (runMap == null || runKey == null) break;
        await _runSync(
          map: runMap,
          sites: _latestSites,
          selectedSite: _latestSelectedSite,
          datasetKey: runKey,
        );
      }
    } finally {
      _syncInFlight = false;
      if (_syncDirty) {
        final map = _latestMap;
        final key = _latestDatasetKey;
        if (map != null && key != null) {
          unawaited(
            sync(
              map: map,
              sites: _latestSites,
              selectedSite: _latestSelectedSite,
              datasetKey: key,
            ),
          );
        }
      }
    }
  }

  Future<void> _runSync({
    required MapboxMap map,
    required List<SiteSummary> sites,
    required SiteSummary? selectedSite,
    required String datasetKey,
  }) async {
    final manager = _manager;
    final shadowManager = _shadowManager;
    final dotManager = _dotManager;
    if (manager == null || shadowManager == null || dotManager == null) {
      return;
    }

    // Capture wipe generation — only abort when [beginDatasetSwitch] bumps it.
    final seq = _syncSeq;

    // Dataset / filter switch → wipe first (before camera), then lazy-fill.
    // [beginDatasetSwitch] may already have wiped; this covers sync-only paths.
    if (_loadedDatasetKey != datasetKey) {
      _selectionAnimToken++;
      await Future.wait([
        shadowManager.deleteAll(),
        manager.deleteAll(),
        dotManager.deleteAll(),
      ]);
      if (seq != _syncSeq) return;
      _bySiteId.clear();
      _shadowBySiteId.clear();
      _byAnnotationId.clear();
      _selectionDot = null;
      _selectedSiteId = null;
      _loadedDatasetKey = datasetKey;
    }

    final camera = await map.getCameraState();
    if (seq != _syncSeq) return;
    final zoom = camera.zoom;
    _baseRadius = mapboxMarkerRadiusForZoom(zoom);
    await Future.wait([
      shadowManager.setCircleRadius(_shadowRadius),
      manager.setCircleRadius(_baseRadius),
      dotManager.setCircleRadius(_dotRadius),
    ]);
    if (seq != _syncSeq) return;

    if (!_rotateModePaused) {
      final selectedId = selectedSite?.siteId;
      if (selectedId != _selectedSiteId) {
        unawaited(applySelectedSiteId(selectedId));
      }
    }

    final desired = <int, SiteSummary>{};
    for (final site in sites) {
      if (site.latitude == null || site.longitude == null) continue;
      desired[site.siteId] = site;
    }

    // Create missing first so pan/scan never flash an empty map.
    final missing = desired.keys
        .where((id) => !_bySiteId.containsKey(id))
        .toList(growable: false);
    for (var i = 0; i < missing.length; i += mapboxMarkerBatchSize) {
      if (seq != _syncSeq) return;
      final chunkIds = missing.skip(i).take(mapboxMarkerBatchSize).toList();
      final fillOptions = <CircleAnnotationOptions>[];
      final shadowOptions = <CircleAnnotationOptions>[];
      final optionSites = <SiteSummary>[];
      for (final siteId in chunkIds) {
        final site = desired[siteId]!;
        final color = periodMarkerColor(site.effectivePeriod);
        final selected = !_rotateModePaused && siteId == _selectedSiteId;
        final point = Point(
          coordinates: Position(site.longitude!, site.latitude!),
        );
        shadowOptions.add(
          CircleAnnotationOptions(
            geometry: point,
            circleSortKey: selected ? 10.0 : 1.0,
          ),
        );
        fillOptions.add(
          CircleAnnotationOptions(
            geometry: point,
            circleColor: color.toARGB32(),
            circleSortKey: selected ? 10.0 : 1.0,
            customData: {'siteId': '$siteId'},
          ),
        );
        optionSites.add(site);
      }
      final created = await Future.wait([
        shadowManager.createMulti(shadowOptions),
        manager.createMulti(fillOptions),
      ]);
      if (seq != _syncSeq) return;
      final shadows = created[0];
      final fills = created[1];
      for (var j = 0; j < fills.length; j++) {
        final fill = fills[j];
        if (fill == null || j >= optionSites.length) continue;
        final site = optionSites[j];
        _bySiteId[site.siteId] = fill;
        _byAnnotationId[fill.id] = site;
        if (j < shadows.length && shadows[j] != null) {
          _shadowBySiteId[site.siteId] = shadows[j]!;
        }
      }
      if (i + mapboxMarkerBatchSize < missing.length) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    // Then prune ids that left the list (viewport replace / filter).
    final staleIds = _bySiteId.keys
        .where((id) => !desired.containsKey(id))
        .toList(growable: false);
    for (var i = 0; i < staleIds.length; i += mapboxMarkerBatchSize) {
      if (seq != _syncSeq) return;
      final chunk = staleIds.skip(i).take(mapboxMarkerBatchSize).toList();
      final fills = <CircleAnnotation>[];
      final shadows = <CircleAnnotation>[];
      for (final siteId in chunk) {
        final fill = _bySiteId.remove(siteId);
        if (fill != null) {
          fills.add(fill);
          _byAnnotationId.remove(fill.id);
        }
        final shadow = _shadowBySiteId.remove(siteId);
        if (shadow != null) shadows.add(shadow);
        if (siteId == _selectedSiteId) {
          _selectedSiteId = null;
          final dot = _selectionDot;
          _selectionDot = null;
          if (dot != null) {
            await dotManager.delete(dot);
            if (seq != _syncSeq) return;
          }
        }
      }
      await Future.wait([
        if (fills.isNotEmpty) manager.deleteMulti(fills),
        if (shadows.isNotEmpty) shadowManager.deleteMulti(shadows),
      ]);
      if (seq != _syncSeq) return;
      if (i + mapboxMarkerBatchSize < staleIds.length) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    for (final entry in desired.entries) {
      final annotation = _bySiteId[entry.key];
      if (annotation != null) {
        _byAnnotationId[annotation.id] = entry.value;
      }
    }

    if (!_rotateModePaused &&
        _selectedSiteId != null &&
        _selectionDot == null) {
      await _syncSelectionDot(siteId: _selectedSiteId);
    }
  }

  /// Instantly apply circle radius for the current zoom (no debounce).
  Future<void> applyZoomRadius(double zoom) async {
    if (_rotateModePaused) return;
    _pendingZoomRadius = zoom;
    if (_radiusInFlight) return;
    _radiusInFlight = true;
    try {
      while (_pendingZoomRadius != null) {
        final manager = _manager;
        final shadowManager = _shadowManager;
        final dotManager = _dotManager;
        if (manager == null || shadowManager == null || dotManager == null) {
          return;
        }
        final nextZoom = _pendingZoomRadius!;
        _pendingZoomRadius = null;
        final radius = mapboxMarkerRadiusForZoom(nextZoom);
        if ((radius - _baseRadius).abs() < 0.02) continue;
        _baseRadius = radius;
        final updates = <Future<void>>[
          shadowManager.setCircleRadius(_shadowRadius),
          manager.setCircleRadius(radius),
          dotManager.setCircleRadius(_dotRadius),
        ];
        final selectionDot = _selectionDot;
        if (selectionDot != null) {
          selectionDot.circleRadius = _dotRadius;
          updates.add(dotManager.update(selectionDot));
        }
        await Future.wait(updates);
      }
    } finally {
      _radiusInFlight = false;
    }
  }

  Future<void> _snapSelection({int? fromId, int? toId}) async {
    final manager = _manager;
    final shadowManager = _shadowManager;
    if (manager == null || shadowManager == null) return;
    if (fromId == toId) return;

    final token = ++_selectionAnimToken;
    final updates = <Future<void>>[];

    if (fromId != null) {
      final fill = _bySiteId[fromId];
      final shadow = _shadowBySiteId[fromId];
      if (fill != null) {
        fill.circleSortKey = 1.0;
        updates.add(manager.update(fill));
      }
      if (shadow != null) {
        shadow.circleSortKey = 1.0;
        updates.add(shadowManager.update(shadow));
      }
    }
    if (toId != null) {
      final fill = _bySiteId[toId];
      final shadow = _shadowBySiteId[toId];
      if (fill != null) {
        fill.circleSortKey = 10.0;
        updates.add(manager.update(fill));
      }
      if (shadow != null) {
        shadow.circleSortKey = 10.0;
        updates.add(shadowManager.update(shadow));
      }
    }
    updates.add(_syncSelectionDot(siteId: toId));
    if (updates.isNotEmpty) await Future.wait(updates);
    if (token != _selectionAnimToken) return;
  }

  Future<void> _syncSelectionDot({required int? siteId}) async {
    final dotManager = _dotManager;
    if (dotManager == null) return;

    if (siteId == null) {
      final existing = _selectionDot;
      if (existing != null) {
        _selectionDot = null;
        await dotManager.delete(existing);
      }
      return;
    }

    final fill = _bySiteId[siteId];
    final geometry = fill?.geometry;
    if (geometry == null) {
      final existing = _selectionDot;
      if (existing != null) {
        _selectionDot = null;
        await dotManager.delete(existing);
      }
      return;
    }

    final existing = _selectionDot;
    if (existing == null) {
      _selectionDot = await dotManager.create(
        CircleAnnotationOptions(
          geometry: geometry,
          circleRadius: _dotRadius,
          circleSortKey: 20.0,
        ),
      );
      return;
    }

    existing.geometry = geometry;
    existing.circleRadius = _dotRadius;
    await dotManager.update(existing);
  }

  void dispose() {
    _syncSeq++;
    _selectionAnimToken++;
    _pendingZoomRadius = null;
    _syncDirty = false;
    _latestMap = null;
    _latestSites = const [];
    _latestSelectedSite = null;
    _latestDatasetKey = null;
    _tapCancelable?.cancel();
    _tapCancelable = null;
    _byAnnotationId.clear();
    _bySiteId.clear();
    _shadowBySiteId.clear();
    _selectionDot = null;
    _loadedDatasetKey = null;
    _selectedSiteId = null;
    _manager = null;
    _shadowManager = null;
    _dotManager = null;
  }
}

typedef ValueChangedSite = void Function(SiteSummary site);

int? _siteIdFromCustomData(Map<String?, Object?>? data) {
  if (data == null) return null;
  final raw = data['siteId'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '');
}

/// Normalizes Mapbox bearing for heading follow (0–360).
double mapboxBearingFromHeading(double headingDeg) {
  var bearing = headingDeg % 360;
  if (bearing < 0) bearing += 360;
  return bearing;
}

/// Clamps zoom into the app's Mapbox-friendly range.
double clampMapboxZoom(double zoom) {
  return zoom.clamp(MapConfig.minZoom, MapConfig.maxZoom);
}

/// Pitch for north-fixed (flat) vs rotate (tilted) mode.
double mapboxPitchForMode({required bool rotateWithHeading}) {
  return rotateWithHeading ? MapConfig.mapboxFollowPitch : 0;
}
