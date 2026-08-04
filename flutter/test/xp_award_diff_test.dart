import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/controllers/auth_controller.dart';
import 'package:mesozoica/models/profile.dart';
import 'package:mesozoica/utils/xp_source_labels.dart';

void main() {
  group('xpSourceLabel', () {
    test('maps known breakdown keys', () {
      expect(xpSourceLabel('site_documentation'), 'Site documentation');
      expect(xpSourceLabel('first_documentation'), 'First documentation');
      expect(xpSourceLabel('site_exploration'), 'Site exploration');
    });

    test('humanizes unknown keys', () {
      expect(xpSourceLabel('custom_source'), 'Custom Source');
    });
  });

  group('AuthController XP award diff', () {
    Profile profile({
      required int xp,
      Map<String, int> breakdown = const {},
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
            'id': 'site_stewardship',
            'name': 'Site Stewardship',
            'xp': xp,
            'level': 1,
            'next_level_xp': 100,
            'xp_to_next': 100,
            'progress': 0,
          },
        ],
        'skill_breakdown': {
          if (breakdown.isNotEmpty) 'site_stewardship': breakdown,
        },
      });
    }

    test('emits one badge per breakdown source', () {
      final before = profile(
        xp: 100,
        breakdown: const {'site_exploration': 40},
      );
      final after = profile(
        xp: 300,
        breakdown: const {
          'site_exploration': 40,
          'site_documentation': 100,
          'first_documentation': 100,
        },
      );

      final awards = AuthController.debugDiffXpAwards(before, after);
      expect(awards, hasLength(2));
      expect(awards.map((a) => a.sourceLabel).toList(), [
        'Site documentation',
        'First documentation',
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
      expect(awards.single.amount, 50);
    });
  });
}
