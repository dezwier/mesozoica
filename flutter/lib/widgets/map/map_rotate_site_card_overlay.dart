import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' hide Position;
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../config/map_config.dart';
import '../../models/site.dart';
import 'map_perf_counters.dart';
import 'map_site_mini_card.dart';

/// A site projected onto the map viewport for photo-pin overlays.
class MapRotateVisibleSite {
  const MapRotateVisibleSite({
    required this.site,
    required this.screenX,
    required this.screenY,
    required this.distanceM,
    required this.cardWidth,
  });

  final SiteSummary site;
  final double screenX;
  final double screenY;
  final double distanceM;
  final double cardWidth;

  double get cardHeight => MapSiteMiniCard.heightForWidth(cardWidth);
  double get layoutWidth => MapSiteMiniCard.layoutWidthFor(cardWidth);
}

/// Fixed pin diameter (no distance scaling).
double rotateMiniCardWidthForDistance(double distanceM) {
  return MapConfig.rotateMiniCardWidth;
}

/// A site kept by the distance cull, with its distance from the cull centre.
typedef RotateCandidate = ({SiteSummary site, double distanceM});

/// Distance-culled, distance-sorted site shortlist for the pin overlay.
///
/// The cull only depends on the cull centre (user location) and the site list,
/// neither of which changes per frame — recomputing it every vsync tick meant
/// a Haversine over the whole loaded catalog at up to 120 Hz. This caches the
/// shortlist and rebuilds it only when the inputs meaningfully change.
class RotateCandidateCache {
  /// Recompute once the cull centre has drifted this far (metres).
  static const double recullMoveM = 25.0;

  List<RotateCandidate> _candidates = const [];
  LatLng? _center;
  List<SiteSummary>? _sites;
  String? _datasetKey;

  /// Cached shortlist (nearest first), capped for projection.
  List<RotateCandidate> get candidates => _candidates;

  /// Drop the shortlist so the next [resolve] recomputes from scratch.
  void invalidate() {
    _center = null;
    _sites = null;
    _datasetKey = null;
    _candidates = const [];
  }

  /// Cull [sites] around [center], reusing the previous result when possible.
  List<RotateCandidate> resolve({
    required List<SiteSummary> sites,
    required LatLng? center,
    String? datasetKey,
  }) {
    if (center == null) {
      invalidate();
      return const [];
    }
    final previousCenter = _center;
    final reusable =
        previousCenter != null &&
        identical(_sites, sites) &&
        _datasetKey == datasetKey &&
        Geolocator.distanceBetween(
              previousCenter.latitude,
              previousCenter.longitude,
              center.latitude,
              center.longitude,
            ) <
            recullMoveM;
    if (reusable) return _candidates;

    final candidates = <RotateCandidate>[];
    for (final site in sites) {
      final lat = site.latitude;
      final lon = site.longitude;
      if (lat == null || lon == null) continue;
      final distanceM = Geolocator.distanceBetween(
        center.latitude,
        center.longitude,
        lat,
        lon,
      );
      // Widen by the re-cull threshold so a site cannot pop in between culls.
      if (distanceM > MapConfig.rotateCardCullRadiusM + recullMoveM) continue;
      candidates.add((site: site, distanceM: distanceM));
    }
    candidates.sort((a, b) => a.distanceM.compareTo(b.distanceM));

    _center = center;
    _sites = sites;
    _datasetKey = datasetKey;
    _candidates = candidates.length > MapConfig.rotateMaxVisibleCards * 2
        ? candidates.sublist(0, MapConfig.rotateMaxVisibleCards * 2)
        : candidates;
    return _candidates;
  }
}

/// Projects the culled [candidates] to those visible for the pin overlay.
///
/// [camera] is the last camera state pushed by Mapbox's camera-change event —
/// [candidates] comes pre-culled and distance-sorted from
/// [RotateCandidateCache], so the only per-frame cost here is one
/// `pixelsForCoordinates` batch over at most `rotateMaxVisibleCards * 2` points.
Future<List<MapRotateVisibleSite>> projectRotateVisibleSites({
  required MapboxMap map,
  required List<RotateCandidate> candidates,
  required ui.Size viewportSize,
}) async {
  if (viewportSize.width <= 0 || viewportSize.height <= 0) return const [];
  if (candidates.isEmpty) return const [];

  final capped = candidates.length > MapConfig.rotateMaxVisibleCards * 2
      ? candidates.sublist(0, MapConfig.rotateMaxVisibleCards * 2)
      : candidates;

  final padX = viewportSize.width * MapConfig.rotateViewportPadding;
  final padY = viewportSize.height * MapConfig.rotateViewportPadding;
  final minX = -padX;
  final maxX = viewportSize.width + padX;
  final minY = -padY;
  final maxY = viewportSize.height + padY;

  final entries = capped;
  final points = <Point>[
    for (final entry in entries)
      Point(coordinates: Position(entry.site.longitude!, entry.site.latitude!)),
  ];

  List<ScreenCoordinate?> pixels;
  try {
    pixels = await map.pixelsForCoordinates(points);
  } catch (_) {
    return const [];
  }

  final visible = <MapRotateVisibleSite>[];
  for (var i = 0; i < entries.length; i++) {
    if (visible.length >= MapConfig.rotateMaxVisibleCards) break;
    final entry = entries[i];
    final pixel = i < pixels.length ? pixels[i] : null;
    if (pixel == null) continue;

    final x = pixel.x.toDouble();
    final y = pixel.y.toDouble();
    if (x < minX || x > maxX || y < minY || y > maxY) continue;

    final cardW = rotateMiniCardWidthForDistance(entry.distanceM);
    final layoutW = MapSiteMiniCard.layoutWidthFor(cardW);
    final layoutH = MapSiteMiniCard.heightForWidth(cardW);
    final anchorX = MapSiteMiniCard.anchorXFor(cardW);
    final left = x - anchorX;
    final top = y - layoutH;
    if (left + layoutW < minX ||
        left > maxX ||
        top + layoutH < minY ||
        top > maxY) {
      continue;
    }

    visible.add(
      MapRotateVisibleSite(
        site: entry.site,
        screenX: x,
        screenY: y,
        distanceM: entry.distanceM,
        cardWidth: cardW,
      ),
    );
  }

  return visible;
}

typedef MapRotateSiteTapCallback = void Function(SiteSummary site);

/// Flutter overlay of upright photo pins (rotate + north-fixed detail zoom).
class MapRotateSiteCardOverlay extends StatelessWidget {
  const MapRotateSiteCardOverlay({
    super.key,
    required this.visibleSites,
    required this.selectedSiteId,
    required this.onSiteTap,
    this.disguisedSiteId,
  });

  final List<MapRotateVisibleSite> visibleSites;
  final int? selectedSiteId;
  final int? disguisedSiteId;
  final MapRotateSiteTapCallback onSiteTap;

  @override
  Widget build(BuildContext context) {
    if (visibleSites.isEmpty) return const SizedBox.shrink();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final entry in visibleSites)
          Positioned(
            left: entry.screenX - MapSiteMiniCard.anchorXFor(entry.cardWidth),
            top: entry.screenY - entry.cardHeight,
            width: entry.layoutWidth,
            height: entry.cardHeight,
            child: _MiniCardTapTarget(
              site: entry.site,
              width: entry.cardWidth,
              distanceM: entry.distanceM,
              selected: entry.site.siteId == selectedSiteId,
              disguised: entry.site.siteId == disguisedSiteId,
              onTap: () => onSiteTap(entry.site),
            ),
          ),
      ],
    );
  }
}

class _MiniCardTapTarget extends StatelessWidget {
  const _MiniCardTapTarget({
    required this.site,
    required this.width,
    required this.distanceM,
    required this.selected,
    required this.disguised,
    required this.onTap,
  });

  final SiteSummary site;
  final double width;
  final double distanceM;
  final bool selected;
  final bool disguised;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: MapSiteMiniCard(
          site: site,
          selected: selected,
          disguised: disguised,
          width: width,
          distanceM: distanceM,
        ),
      ),
    );
  }
}

/// Frame-synced projection driver for pin overlays.
class MapRotateOverlayController {
  MapRotateOverlayController({required this.onVisibleSitesChanged});

  final ValueChanged<List<MapRotateVisibleSite>> onVisibleSitesChanged;

  final RotateCandidateCache _candidateCache = RotateCandidateCache();

  int _syncSeq = 0;
  bool _syncInFlight = false;
  bool _syncQueued = false;
  List<SiteSummary> _queuedSites = const [];
  ui.Size? _queuedViewportSize;
  LatLng? _queuedCullCenter;
  String? _queuedDatasetKey;

  /// Projections actually run (perf HUD diffs this over a window).
  int _projectionCount = 0;
  int get projectionCount => _projectionCount;

  /// Force a full re-cull on the next frame (dataset / filter switch).
  void invalidateCandidates() => _candidateCache.invalidate();

  void syncFrame({
    required MapboxMap? map,
    required List<SiteSummary> sites,
    required ui.Size viewportSize,
    LatLng? cullCenter,
    String? datasetKey,
  }) {
    // Keep the newest inputs so a coalesced re-run projects current state
    // rather than replaying the arguments of the call that was in flight.
    _queuedSites = sites;
    _queuedViewportSize = viewportSize;
    _queuedCullCenter = cullCenter;
    _queuedDatasetKey = datasetKey;
    unawaited(_sync(map: map));
  }

  Future<void> _sync({required MapboxMap? map}) async {
    if (_syncInFlight) {
      _syncQueued = true;
      return;
    }
    _syncInFlight = true;
    try {
      do {
        _syncQueued = false;
        final seq = ++_syncSeq;
        final viewportSize = _queuedViewportSize;
        if (map == null || viewportSize == null) {
          onVisibleSitesChanged(const []);
          continue;
        }
        final candidates = _candidateCache.resolve(
          sites: _queuedSites,
          center: _queuedCullCenter,
          datasetKey: _queuedDatasetKey,
        );
        if (candidates.isEmpty) {
          onVisibleSitesChanged(const []);
          continue;
        }
        _projectionCount++;
        MapPerfCounters.countOverlayProjection();
        final projected = await projectRotateVisibleSites(
          map: map,
          candidates: candidates,
          viewportSize: viewportSize,
        );
        if (seq != _syncSeq) continue;
        onVisibleSitesChanged(projected);
      } while (_syncQueued);
    } finally {
      _syncInFlight = false;
    }
  }

  void dispose() {
    _syncSeq++;
    _candidateCache.invalidate();
  }
}

/// Sort overlay cards back-to-front by distance so nearer cards receive taps.
List<MapRotateVisibleSite> sortOverlayDepth(List<MapRotateVisibleSite> sites) {
  final copy = List<MapRotateVisibleSite>.from(sites);
  copy.sort((a, b) => b.distanceM.compareTo(a.distanceM));
  return copy;
}

/// Skip [setState] when overlay geometry and visible site content are unchanged.
bool rotateOverlaySitesEqual(
  List<MapRotateVisibleSite> a,
  List<MapRotateVisibleSite> b, {
  double epsilon = 0.5,
}) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  final byId = {for (final s in b) s.site.siteId: s};
  for (final site in a) {
    final other = byId[site.site.siteId];
    if (other == null) return false;
    if (!_markerPresentationEqual(site.site, other.site)) return false;
    if ((site.screenX - other.screenX).abs() > epsilon) return false;
    if ((site.screenY - other.screenY).abs() > epsilon) return false;
    if ((site.cardWidth - other.cardWidth).abs() > epsilon) return false;
  }
  return true;
}

bool _markerPresentationEqual(SiteSummary a, SiteSummary b) {
  return a.displayTitle == b.displayTitle &&
      a.status == b.status &&
      a.documented == b.documented &&
      a.viewerHasDocumented == b.viewerHasDocumented &&
      a.documentationStars == b.documentationStars &&
      a.mainImageUrl == b.mainImageUrl;
}
