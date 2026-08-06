import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesozoica/config/map_config.dart';
import 'package:mesozoica/models/site.dart';
import 'package:mesozoica/widgets/map/map_rotate_site_card_overlay.dart';

/// Metres per degree of latitude — close enough to place fixtures precisely.
const _mPerDegLat = 111320.0;

LatLng _northOf(LatLng origin, double metres) =>
    LatLng(origin.latitude + metres / _mPerDegLat, origin.longitude);

SiteSummary _site(int id, LatLng at) =>
    SiteSummary(siteId: id, latitude: at.latitude, longitude: at.longitude);

void main() {
  const origin = LatLng(51.0, 4.0);

  group('RotateCandidateCache', () {
    test('culls beyond the rotate radius and sorts nearest first', () {
      final sites = [
        _site(3, _northOf(origin, 900)),
        _site(1, _northOf(origin, 100)),
        _site(2, _northOf(origin, 400)),
        // Well beyond rotateCardCullRadiusM (1500 m) plus the re-cull margin.
        _site(4, _northOf(origin, 5000)),
      ];

      final result = RotateCandidateCache().resolve(
        sites: sites,
        center: origin,
        datasetKey: 'field:linked',
      );

      expect(result.map((c) => c.site.siteId), [1, 2, 3]);
      expect(result.first.distanceM, lessThan(result.last.distanceM));
    });

    test('reuses the shortlist for sub-threshold movement', () {
      final cache = RotateCandidateCache();
      final sites = [_site(1, _northOf(origin, 100))];

      final first = cache.resolve(
        sites: sites,
        center: origin,
        datasetKey: 'field:linked',
      );
      final second = cache.resolve(
        sites: sites,
        center: _northOf(origin, RotateCandidateCache.recullMoveM - 5),
        datasetKey: 'field:linked',
      );

      // Identity, not equality: the whole point is that no work was redone.
      expect(identical(first, second), isTrue);
    });

    test('re-culls once the centre drifts past the threshold', () {
      final cache = RotateCandidateCache();
      final sites = [_site(1, _northOf(origin, 100))];

      final first = cache.resolve(
        sites: sites,
        center: origin,
        datasetKey: 'field:linked',
      );
      final moved = _northOf(origin, RotateCandidateCache.recullMoveM + 10);
      final second = cache.resolve(
        sites: sites,
        center: moved,
        datasetKey: 'field:linked',
      );

      expect(identical(first, second), isFalse);
      // Walked toward the site, so the recorded distance must have shrunk.
      expect(second.single.distanceM, lessThan(first.single.distanceM));
    });

    test('re-culls when the site list identity changes', () {
      final cache = RotateCandidateCache();
      final first = cache.resolve(
        sites: [_site(1, _northOf(origin, 100))],
        center: origin,
        datasetKey: 'field:linked',
      );
      final second = cache.resolve(
        sites: [
          _site(1, _northOf(origin, 100)),
          _site(2, _northOf(origin, 200)),
        ],
        center: origin,
        datasetKey: 'field:linked',
      );

      expect(first, hasLength(1));
      expect(second, hasLength(2));
    });

    test('re-culls when the dataset key changes', () {
      final cache = RotateCandidateCache();
      final sites = [_site(1, _northOf(origin, 100))];

      final first = cache.resolve(
        sites: sites,
        center: origin,
        datasetKey: 'field:linked',
      );
      final second = cache.resolve(
        sites: sites,
        center: origin,
        datasetKey: 'archive:0|all',
      );

      expect(identical(first, second), isFalse);
    });

    test('keeps a margin beyond the cull radius so pins cannot pop in', () {
      // A site just outside the radius must still be retained, because the
      // centre may drift up to recullMoveM before the next cull runs.
      final justOutside = _northOf(
        origin,
        MapConfig.rotateCardCullRadiusM + RotateCandidateCache.recullMoveM / 2,
      );
      final result = RotateCandidateCache().resolve(
        sites: [_site(1, justOutside)],
        center: origin,
        datasetKey: 'field:linked',
      );

      expect(result, hasLength(1));
    });

    test('caps the shortlist at twice the visible card budget', () {
      final sites = [
        for (var i = 0; i < MapConfig.rotateMaxVisibleCards * 4; i++)
          _site(i, _northOf(origin, 10.0 * (i + 1))),
      ];

      final result = RotateCandidateCache().resolve(
        sites: sites,
        center: origin,
        datasetKey: 'field:linked',
      );

      expect(result, hasLength(MapConfig.rotateMaxVisibleCards * 2));
      // Capping must keep the nearest sites, not an arbitrary slice.
      expect(result.first.site.siteId, 0);
    });

    test('a null centre yields no candidates and clears the cache', () {
      final cache = RotateCandidateCache();
      cache.resolve(
        sites: [_site(1, _northOf(origin, 100))],
        center: origin,
        datasetKey: 'field:linked',
      );

      expect(cache.resolve(sites: const [], center: null), isEmpty);
      expect(cache.candidates, isEmpty);
    });

    test('invalidate forces a fresh cull for identical inputs', () {
      final cache = RotateCandidateCache();
      final sites = [_site(1, _northOf(origin, 100))];

      final first = cache.resolve(
        sites: sites,
        center: origin,
        datasetKey: 'field:linked',
      );
      cache.invalidate();
      final second = cache.resolve(
        sites: sites,
        center: origin,
        datasetKey: 'field:linked',
      );

      expect(identical(first, second), isFalse);
      expect(second.single.site.siteId, 1);
    });
  });
}
