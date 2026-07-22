import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/services/health_distance_service.dart';

void main() {
  test('localWeekStartMonday snaps to Monday 00:00 local', () {
    // Wednesday 2026-07-22
    final wednesday = DateTime(2026, 7, 22, 15, 30);
    final start = localWeekStartMonday(wednesday);
    expect(start.year, 2026);
    expect(start.month, 7);
    expect(start.day, 20);
    expect(start.weekday, DateTime.monday);
    expect(start.hour, 0);
    expect(start.minute, 0);
  });

  test('localWeekStartMonday keeps Monday itself', () {
    final monday = DateTime(2026, 7, 20, 8, 0);
    final start = localWeekStartMonday(monday);
    expect(start.day, 20);
    expect(weekStartIso(monday), '2026-07-20');
  });

  test('localWeekStartMonday handles Sunday as previous Monday', () {
    final sunday = DateTime(2026, 7, 26, 23, 59);
    final start = localWeekStartMonday(sunday);
    expect(start.day, 20);
    expect(weekStartIso(sunday), '2026-07-20');
  });
}
