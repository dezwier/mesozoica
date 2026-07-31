import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' hide Position;
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../config/map_config.dart';
import '../../models/site.dart';
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

/// Projects and culls [sites] to those visible for the pin overlay.
Future<List<MapRotateVisibleSite>> projectRotateVisibleSites({
  required MapboxMap map,
  required List<SiteSummary> sites,
  required ui.Size viewportSize,
  LatLng? cullCenter,
}) async {
  if (viewportSize.width <= 0 || viewportSize.height <= 0) return const [];

  CameraState camera;
  try {
    camera = await map.getCameraState();
  } catch (_) {
    return const [];
  }

  final center = cullCenter ??
      LatLng(
        camera.center.coordinates.lat.toDouble(),
        camera.center.coordinates.lng.toDouble(),
      );

  final candidates = <({SiteSummary site, double distanceM})>[];
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
    if (distanceM > MapConfig.rotateCardCullRadiusM) continue;
    candidates.add((site: site, distanceM: distanceM));
  }

  if (candidates.isEmpty) return const [];

  candidates.sort((a, b) => a.distanceM.compareTo(b.distanceM));
  final capped = candidates.take(MapConfig.rotateMaxVisibleCards * 2).toList();

  final padX = viewportSize.width * MapConfig.rotateViewportPadding;
  final padY = viewportSize.height * MapConfig.rotateViewportPadding;
  final minX = -padX;
  final maxX = viewportSize.width + padX;
  final minY = -padY;
  final maxY = viewportSize.height + padY;

  final points = <Point>[];
  final entries = <({SiteSummary site, double distanceM})>[];
  for (final entry in capped) {
    final site = entry.site;
    points.add(
      Point(coordinates: Position(site.longitude!, site.latitude!)),
    );
    entries.add(entry);
  }

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
    required this.hiddenSiteId,
    required this.onSiteTap,
  });

  final List<MapRotateVisibleSite> visibleSites;
  final int? selectedSiteId;
  final int? hiddenSiteId;
  final MapRotateSiteTapCallback onSiteTap;

  @override
  Widget build(BuildContext context) {
    if (visibleSites.isEmpty) return const SizedBox.shrink();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final entry in visibleSites)
          if (entry.site.siteId != hiddenSiteId)
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
    required this.onTap,
  });

  final SiteSummary site;
  final double width;
  final double distanceM;
  final bool selected;
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
          width: width,
          distanceM: distanceM,
        ),
      ),
    );
  }
}

/// Frame-synced projection driver for pin overlays.
class MapRotateOverlayController {
  MapRotateOverlayController({
    required this.onVisibleSitesChanged,
  });

  final ValueChanged<List<MapRotateVisibleSite>> onVisibleSitesChanged;

  int _syncSeq = 0;
  bool _syncInFlight = false;
  bool _syncQueued = false;

  void syncFrame({
    required MapboxMap? map,
    required List<SiteSummary> sites,
    required ui.Size viewportSize,
    LatLng? cullCenter,
  }) {
    unawaited(
      _sync(
        map: map,
        sites: sites,
        viewportSize: viewportSize,
        cullCenter: cullCenter,
      ),
    );
  }

  Future<void> _sync({
    required MapboxMap? map,
    required List<SiteSummary> sites,
    required ui.Size viewportSize,
    LatLng? cullCenter,
  }) async {
    if (_syncInFlight) {
      _syncQueued = true;
      return;
    }
    _syncInFlight = true;
    try {
      do {
        _syncQueued = false;
        final seq = ++_syncSeq;
        if (map == null) {
          onVisibleSitesChanged(const []);
          continue;
        }
        final projected = await projectRotateVisibleSites(
          map: map,
          sites: sites,
          viewportSize: viewportSize,
          cullCenter: cullCenter,
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
  }
}

/// Sort overlay cards back-to-front by distance so nearer cards receive taps.
List<MapRotateVisibleSite> sortOverlayDepth(List<MapRotateVisibleSite> sites) {
  final copy = List<MapRotateVisibleSite>.from(sites);
  copy.sort((a, b) => b.distanceM.compareTo(a.distanceM));
  return copy;
}

/// Skip [setState] when overlay geometry is unchanged between frames.
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
    if ((site.screenX - other.screenX).abs() > epsilon) return false;
    if ((site.screenY - other.screenY).abs() > epsilon) return false;
    if ((site.cardWidth - other.cardWidth).abs() > epsilon) return false;
  }
  return true;
}
