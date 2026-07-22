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
}
