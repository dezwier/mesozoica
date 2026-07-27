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
  });

  test('Profile parses skill leveling fields', () {
    final profile = Profile.fromJson({
      'id': 1,
      'display_name': 'Scout',
      'exploration_xp': 130,
      'excavation_xp': 0,
      'research_xp': 0,
      'exploration_level': 2,
      'excavation_level': 1,
      'research_level': 1,
      'career_title': 'Path Dust Note',
      'exploration_progress': 0.4,
      'excavation_progress': 0.0,
      'research_progress': 0.0,
      'career_progress': 0.2,
      'xp_from_sites': 30,
      'xp_from_fossils': 50,
      'xp_from_active_distance': 30,
      'xp_from_passive_distance': 20,
      'xp': 130,
      'level': 1,
    });

    expect(profile.explorationXp, 130);
    expect(profile.explorationLevel, 2);
    expect(profile.careerTitle, 'Path Dust Note');
    expect(profile.xpFromSites, 30);
    expect(profile.xpFromFossils, 50);
    expect(profile.xpFromActiveDistance, 30);
    expect(profile.xpFromPassiveDistance, 20);
    expect(profile.careerProgress, 0.2);
  });
}
