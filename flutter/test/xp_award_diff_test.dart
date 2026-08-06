import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/controllers/auth_controller.dart';
import 'package:mesozoica/controllers/xp_award_controller.dart';
import 'package:mesozoica/models/profile.dart';
import 'package:mesozoica/utils/xp_source_labels.dart';

void main() {
  group('xpSourceLabel', () {
    test('maps known breakdown keys', () {
      expect(xpSourceLabel('document_site'), 'Document site');
      expect(xpSourceLabel('document_site_as_first'), 'Document site as first');
      expect(xpSourceLabel('document_progress'), 'Document progress');
    });

    test('humanizes unknown keys', () {
      expect(xpSourceLabel('custom_source'), 'Custom Source');
    });

    test('distance awards use meters inferred from XP amount', () {
      expect(
        xpSourceLabelForAward('explore_100m_passively', 10),
        'Explore 100 m passively',
      );
      expect(
        xpSourceLabelForAward('explore_100m_passively', 50),
        'Explore 500 m passively',
      );
      expect(
        xpSourceLabelForAward('explore_100m_actively', 40),
        'Explore 200 m actively',
      );
    });
  });

  group('celebration vs badge classification', () {
    test('marks celebration-bound keys', () {
      expect(isCelebrationXpSource('discover_site'), isTrue);
      expect(isCelebrationXpSource('discover_site_as_first'), isTrue);
      expect(isCelebrationXpSource('locate_fossil_in_situ'), isTrue);
      expect(isCelebrationXpSource('document_site'), isTrue);
      expect(isCelebrationXpSource('document_site_as_first'), isTrue);
      expect(isCelebrationXpSource('identify_site'), isTrue);
    });

    test('marks badge-only keys', () {
      expect(isCelebrationXpSource('explore_100m_actively'), isFalse);
      expect(isCelebrationXpSource('explore_100m_passively'), isFalse);
      expect(isCelebrationXpSource('disguise_of_site'), isFalse);
      expect(isCelebrationXpSource('document_progress'), isFalse);
      expect(isCelebrationXpSource(''), isFalse);
      expect(isCelebrationXpSource(null), isFalse);
    });
  });

  group('AuthController XP award diff', () {
    Profile profile({
      required int xp,
      Map<String, int> breakdown = const {},
      String skillId = 'site_stewardship',
      String skillName = 'Site Stewardship',
    }) {
      return Profile.fromJson({
        'id': 1,
        'display_name': 'Tester',
        'email': 'a@b.c',
        'username': 'tester',
        'xp': xp,
        'level': 1,
        'skills': [
          {
            'id': skillId,
            'name': skillName,
            'xp': xp,
            'level': 1,
            'next_level_xp': 100,
            'xp_to_next': 100,
            'progress': 0,
          },
        ],
        'skill_breakdown': {
          if (breakdown.isNotEmpty) skillId: breakdown,
        },
      });
    }

    test('emits one award per breakdown source with sourceKey', () {
      final before = profile(
        xp: 100,
        breakdown: const {'document_progress': 40},
      );
      final after = profile(
        xp: 300,
        breakdown: const {
          'document_progress': 40,
          'document_site': 100,
          'document_site_as_first': 100,
        },
      );

      final awards = AuthController.debugDiffXpAwards(before, after);
      expect(awards, hasLength(2));
      expect(awards.map((a) => a.sourceKey).toList(), [
        'document_site',
        'document_site_as_first',
      ]);
      expect(awards.map((a) => a.sourceLabel).toList(), [
        'Document site',
        'Document site as first',
      ]);
      expect(awards.map((a) => a.amount).toList(), [100, 100]);
      expect(awards.every((a) => a.skillId == 'site_stewardship'), isTrue);
    });

    test('falls back to skill name when breakdown is missing', () {
      final before = profile(xp: 100);
      final after = profile(xp: 150);

      final awards = AuthController.debugDiffXpAwards(before, after);
      expect(awards, hasLength(1));
      expect(awards.single.sourceLabel, 'Site Stewardship');
      expect(awards.single.sourceKey, '');
      expect(awards.single.amount, 50);
    });

    test('distance award labels include meters inferred from XP', () {
      final before = profile(
        xp: 0,
        breakdown: const {},
        skillId: 'field_survey',
        skillName: 'Field Survey',
      );
      final after = profile(
        xp: 50,
        breakdown: const {'explore_100m_passively': 50},
        skillId: 'field_survey',
        skillName: 'Field Survey',
      );

      final awards = AuthController.debugDiffXpAwards(before, after);
      expect(awards, hasLength(1));
      expect(awards.single.sourceLabel, 'Explore 500 m passively');
      expect(awards.single.amount, 50);
    });
  });

  group('XpAwardController announce / claim', () {
    XpAward award({
      required String sourceKey,
      required int amount,
      String skillId = 'site_discovery',
      String skillName = 'Site Discovery',
    }) {
      return XpAward(
        id: 0,
        skillId: skillId,
        skillName: skillName,
        sourceLabel: sourceKey.isEmpty
            ? skillName
            : xpSourceLabelForAward(sourceKey, amount),
        amount: amount,
        sourceKey: sourceKey,
      );
    }

    test('partitions celebration sources to stash and badge sources to overlay',
        () {
      // Every announced award goes to exactly one path: celebration or badge.
      final controller = XpAwardController();
      controller.announceAwards([
        award(sourceKey: 'discover_site', amount: 20),
        award(sourceKey: 'discover_site_as_first', amount: 20),
        award(sourceKey: 'explore_100m_actively', amount: 30),
        award(
          sourceKey: 'document_progress',
          amount: 20,
          skillId: 'site_stewardship',
        ),
      ]);

      expect(controller.activeAwards, hasLength(2));
      expect(
        controller.activeAwards.map((a) => a.sourceKey).toSet(),
        {'explore_100m_actively', 'document_progress'},
      );
      expect(controller.celebrationStash, hasLength(2));
      expect(
        controller.celebrationStash.map((a) => a.sourceKey).toSet(),
        {'discover_site', 'discover_site_as_first'},
      );
    });

    test('claim consumes matching keys and leaves others', () {
      final controller = XpAwardController();
      controller.announceAwards([
        award(sourceKey: 'discover_site', amount: 20),
        award(sourceKey: 'locate_fossil_in_situ', amount: 40, skillId: 'bone_quarry'),
        award(sourceKey: 'discover_site_as_first', amount: 20),
        award(sourceKey: 'document_site', amount: 80, skillId: 'site_stewardship'),
      ]);

      final claimed = controller.claimCelebrationAwards(
        kSiteDiscoveryCelebrationXpKeys,
      );
      expect(claimed.map((a) => a.sourceKey).toList(), [
        'discover_site',
        'locate_fossil_in_situ',
        'discover_site_as_first',
      ]);
      expect(controller.celebrationStash, hasLength(1));
      expect(controller.celebrationStash.single.sourceKey, 'document_site');
    });

    test('identification merge sums multiple identify_site awards', () {
      final controller = XpAwardController();
      controller.announceAwards([
        award(
          sourceKey: 'identify_site',
          amount: 40,
          skillId: 'site_stewardship',
        ),
        award(
          sourceKey: 'identify_site',
          amount: 20,
          skillId: 'site_stewardship',
        ),
      ]);

      final claimed = controller.claimCelebrationAwards(
        kSiteIdentificationCelebrationXpKeys,
        mergeSameKey: true,
      );
      expect(claimed, hasLength(1));
      expect(claimed.single.sourceKey, 'identify_site');
      expect(claimed.single.amount, 60);
      expect(controller.celebrationStash, isEmpty);
    });

    test('visit announce merges distance into explored-since-last-visit badge',
        () {
      final controller = XpAwardController();
      controller.announceAwardsAfterVisit(
        awards: [
          award(sourceKey: 'explore_100m_passively', amount: 100),
          award(sourceKey: 'explore_100m_actively', amount: 40),
          award(sourceKey: 'disguise_of_site', amount: 10),
        ],
        exploredMeters: 1500,
      );

      expect(controller.activeAwards, hasLength(2));
      final visit = controller.activeAwards.firstWhere(
        (a) => a.sourceLabel.startsWith('Explored '),
      );
      expect(visit.sourceLabel, 'Explored 1.5 km since last visit');
      expect(visit.amount, 140);
      expect(
        controller.activeAwards.any((a) => a.sourceKey == 'disguise_of_site'),
        isTrue,
      );
    });

    test('visit announce with only passive uses explore-distance label', () {
      final controller = XpAwardController();
      controller.announceAwardsAfterVisit(
        awards: [
          award(sourceKey: 'explore_100m_passively', amount: 100),
        ],
        exploredMeters: 1500,
      );

      expect(controller.activeAwards, hasLength(1));
      expect(
        controller.activeAwards.single.sourceLabel,
        'Explore 1.5 km passively',
      );
      expect(controller.activeAwards.single.amount, 100);
    });

    test('visit announce shows distance-only badge when XP is 0', () {
      final controller = XpAwardController();
      controller.announceAwardsAfterVisit(
        awards: const [],
        exploredMeters: 250,
      );

      expect(controller.activeAwards, hasLength(1));
      expect(
        controller.activeAwards.single.sourceLabel,
        'Explored 250 m since last visit',
      );
      expect(controller.activeAwards.single.amount, 0);
    });

    test('visit announce with under 10 m falls back to normal announce', () {
      final controller = XpAwardController();
      controller.announceAwardsAfterVisit(
        awards: [award(sourceKey: 'explore_100m_passively', amount: 1)],
        exploredMeters: 9,
      );

      expect(controller.activeAwards, hasLength(1));
      expect(
        controller.activeAwards.single.sourceLabel,
        'Explore 10 m passively',
      );
      expect(controller.activeAwards.single.amount, 1);
    });

    test('visit announce with 0 meters falls back to normal announce', () {
      final controller = XpAwardController();
      controller.announceAwardsAfterVisit(
        awards: [award(sourceKey: 'explore_100m_passively', amount: 100)],
        exploredMeters: 0,
      );

      expect(controller.activeAwards, hasLength(1));
      expect(
        controller.activeAwards.single.sourceLabel,
        'Explore 1.0 km passively',
      );
    });

    test('clear empties active badges and celebration stash', () {
      final controller = XpAwardController();
      controller.announceAwards([
        award(sourceKey: 'discover_site', amount: 20),
        award(sourceKey: 'disguise_of_site', amount: 50, skillId: 'site_stewardship'),
      ]);
      controller.clear();
      expect(controller.activeAwards, isEmpty);
      expect(controller.celebrationStash, isEmpty);
    });

    test('background holds document progress and active explore, flushes merged',
        () {
      final controller = XpAwardController();
      controller.setAppForeground(false);

      controller.announceAwards([
        award(sourceKey: 'document_progress', amount: 20),
        award(sourceKey: 'explore_100m_actively', amount: 20),
      ]);
      controller.announceAwards([
        award(sourceKey: 'document_progress', amount: 20),
        award(sourceKey: 'explore_100m_actively', amount: 20),
        award(sourceKey: 'document_progress', amount: 20),
      ]);
      // Non-bundlable badge sources still show immediately.
      controller.announceAwards([
        award(
          sourceKey: 'disguise_of_site',
          amount: 10,
          skillId: 'site_stewardship',
        ),
      ]);

      expect(controller.activeAwards, hasLength(1));
      expect(controller.activeAwards.single.sourceKey, 'disguise_of_site');
      expect(controller.backgroundBundle, hasLength(2));

      controller.setAppForeground(true);

      expect(controller.backgroundBundle, isEmpty);
      expect(controller.activeAwards, hasLength(3));
      final byKey = {
        for (final a in controller.activeAwards) a.sourceKey: a.amount,
      };
      expect(byKey['disguise_of_site'], 10);
      expect(byKey['document_progress'], 60);
      expect(byKey['explore_100m_actively'], 40);
    });

    test('foreground still shows each batch immediately', () {
      final controller = XpAwardController();
      controller.announceAwards([
        award(sourceKey: 'document_progress', amount: 20),
      ]);
      controller.announceAwards([
        award(sourceKey: 'document_progress', amount: 20),
      ]);

      expect(controller.activeAwards, hasLength(2));
      expect(controller.backgroundBundle, isEmpty);
    });
  });

  group('explored since last visit labels', () {
    test('formats meters and km', () {
      expect(formatExplorationDistance(42), '42 m');
      expect(formatExplorationDistance(1500), '1.5 km');
      expect(formatExplorationDistance(12500), '13 km');
      expect(
        exploredSinceLastVisitLabel(800),
        'Explored 800 m since last visit',
      );
    });
  });
}
