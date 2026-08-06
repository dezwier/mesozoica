import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mesozoica/features/discovery/discovery.dart';
import 'package:shared_preferences/shared_preferences.dart';

Position _position(double latitude, double longitude) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime.utc(2026, 8, 6),
    accuracy: 1,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

SiteSummary _site(int id, double latitude, double longitude) {
  return SiteSummary(
    siteId: id,
    latitude: latitude,
    longitude: longitude,
    status: 'identified',
    discoveredAt: DateTime.utc(2026, 8, 6),
    viewerHasIdentified: true,
    documentationProgress: 0,
    oddDinoCount: 0.5,
    oddFossilCount: 0.5,
    oddCompleteness: 0.5,
    oddQuality: 0.5,
    oddDepth: 0.5,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('migrates legacy explored meters to unit-interval progress', () async {
    SharedPreferences.setMockInitialValues({
      'site_exploration_v1': jsonEncode({'7': 30.0, '8': 200.0}),
    });
    final controller = SiteExplorationController();
    await controller.debugInitializeForTest(
      discoveredSitesProvider: () => const [],
    );

    expect(controller.progressBySite[7], closeTo(0.3, 1e-9));
    expect(controller.progressBySite[8], 1.0);
    controller.dispose();
  });

  test(
    'standing in range credits every eligible site by elapsed time',
    () async {
      final sites = [_site(1, 50, 4), _site(2, 50.0001, 4.0001)];
      final controller = SiteExplorationController();
      controller.updateSiteVisibilityM(50);
      controller.updateDiscoverySpeed(0.01);
      await controller.debugInitializeForTest(
        discoveredSitesProvider: () => sites,
      );

      await controller.debugCreditElapsed(
        position: _position(50, 4),
        elapsed: const Duration(seconds: 3),
      );

      expect(controller.documentationProgressFor(1), closeTo(0.03, 1e-9));
      expect(controller.documentationProgressFor(2), closeTo(0.03, 1e-9));
      expect(controller.isInDocumentationRange(1), isTrue);
      expect(controller.isInDocumentationRange(2), isTrue);
      controller.dispose();
    },
  );

  test('leaving range pauses progress and clears active card state', () async {
    final site = _site(1, 50, 4);
    final controller = SiteExplorationController();
    controller.updateSiteVisibilityM(50);
    await controller.debugInitializeForTest(
      discoveredSitesProvider: () => [site],
    );
    await controller.debugCreditElapsed(
      position: _position(50, 4),
      elapsed: const Duration(seconds: 1),
    );
    final before = controller.documentationProgressFor(1);

    await controller.debugCreditElapsed(
      position: _position(51, 4),
      elapsed: const Duration(seconds: 20),
    );

    expect(controller.documentationProgressFor(1), before);
    expect(controller.isInDocumentationRange(1), isFalse);
    controller.dispose();
  });

  test('background interval requires both bounding fixes in range', () async {
    final site = _site(1, 50, 4);
    final controller = SiteExplorationController();
    controller.updateSiteVisibilityM(50);
    await controller.debugInitializeForTest(
      discoveredSitesProvider: () => [site],
    );

    await controller.debugCreditElapsed(
      startPosition: _position(51, 4),
      position: _position(50, 4),
      elapsed: const Duration(seconds: 30),
    );

    expect(controller.documentationProgressFor(1), 0);
    controller.dispose();
  });

  test(
    'resume credits time spent backgrounded when both fixes are in range',
    () async {
      final site = _site(1, 50, 4);
      var now = DateTime.utc(2026, 8, 6, 12);
      final controller = SiteExplorationController(now: () => now);
      controller.updateSiteVisibilityM(50);
      controller.updateDiscoverySpeed(0.01);
      await controller.debugInitializeForTest(
        discoveredSitesProvider: () => [site],
      );
      controller.debugSetVerifiedFix(_position(50, 4), now);

      await controller.onAppBackgrounded();
      now = now.add(const Duration(seconds: 12));
      controller.onAppResumed();
      await controller.debugHandleFreshFix(_position(50.00001, 4.00001));

      expect(controller.documentationProgressFor(1), closeTo(0.12, 1e-9));
      controller.dispose();
    },
  );

  test(
    'sync sends progress contract and queues completion celebration',
    () async {
      final site = _site(1, 50, 4);
      Map<String, dynamic>? sentBody;
      final controller = SiteExplorationController(
        patchRequest: (path, body) async {
          expect(path, '/api/v1/users/me/site-exploration');
          sentBody = body;
          return {
            'sites': [
              {'site_id': 1, 'documentation_progress': 1.0, 'documented': true},
            ],
          };
        },
      );
      controller.updateDiscoverySpeed(1);
      await controller.debugInitializeForTest(
        discoveredSitesProvider: () => [site],
      );
      await controller.debugCreditElapsed(
        position: _position(50, 4),
        elapsed: const Duration(seconds: 1),
      );

      final locallyCompleted = controller.resolveSite(site);
      expect(locallyCompleted.documented, isTrue);
      expect(locallyCompleted.status, 'documented');

      await controller.debugSync();

      expect(sentBody, {
        'sites': [
          {'site_id': 1, 'documentation_progress': 1.0},
        ],
      });
      expect(controller.pendingDocumentationCelebration?.siteId, 1);
      controller.consumeDocumentationCelebration();
      expect(controller.pendingDocumentationCelebration, isNull);
      controller.dispose();
    },
  );
}
