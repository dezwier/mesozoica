import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/profile.dart';

void main() {
  test('Profile parses createdAt and distance fields', () {
    final profile = Profile.fromJson({
      'id': 7,
      'display_name': 'Walker',
      'username': 'walker',
      'email': 'w@example.com',
      'created_at': '2026-01-15T12:00:00+00:00',
      'total_distance_m': 12345.5,
      'weekly_distance_m': 2100,
      'active_distance_m': 8000,
      'active_weekly_distance_m': 1500,
      'distance_week_start': '2026-07-20',
      'level': 3,
      'xp': 100,
    });

    expect(profile.createdAt, isNotNull);
    expect(profile.createdAt!.toUtc().year, 2026);
    expect(profile.createdAt!.toUtc().month, 1);
    expect(profile.createdAt!.toUtc().day, 15);
    expect(profile.totalDistanceM, 12345.5);
    expect(profile.weeklyDistanceM, 2100);
    expect(profile.activeDistanceM, 8000);
    expect(profile.activeWeeklyDistanceM, 1500);
    expect(profile.distanceWeekStart, '2026-07-20');
  });

  test('Profile parses multi-skill leveling fields', () {
    final profile = Profile.fromJson({
      'id': 1,
      'display_name': 'Scout',
      'career_title': 'Curious Wanderer',
      'career': {
        'xp': 130,
        'level': 1,
        'title': 'Curious Wanderer',
        'next_level_xp': 913,
        'xp_to_next': 783,
        'progress': 0.2,
      },
      'skills': [
        {
          'id': 'site_discovery',
          'name': 'Site Discovery',
          'xp': 75,
          'level': 1,
          'next_level_xp': 83,
          'xp_to_next': 8,
          'progress': 0.9,
        },
        {
          'id': 'fossil_detection',
          'name': 'Fossil Detection',
          'xp': 55,
          'level': 1,
          'next_level_xp': 83,
          'xp_to_next': 28,
          'progress': 0.66,
        },
      ],
      'skill_breakdown': {
        'site_discovery': {
          'sites': 20,
          'active_distance': 30,
          'passive_distance': 25,
        },
        'fossil_detection': {'fossils': 55},
      },
      'xp': 130,
      'level': 1,
    });

    expect(profile.effectiveCareer.xp, 130);
    expect(profile.effectiveCareer.progress, 0.2);
    expect(profile.careerTitle, 'Curious Wanderer');
    expect(profile.skills.length, 2);
    expect(profile.skills.first.id, 'site_discovery');
    expect(profile.skillBreakdown['site_discovery']?['sites'], 20);
    expect(profile.skillBreakdown['fossil_detection']?['fossils'], 55);
  });
}
