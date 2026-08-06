import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/controllers/walk_distance_controller.dart';
import 'package:mesozoica/models/profile.dart';
import 'package:mesozoica/services/gps_odometer.dart';
import 'package:mesozoica/services/health_distance_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHealth extends HealthDistanceService {
  _FakeHealth({
    this.gapMeters = 0,
    this.permission = HealthDistancePermission.granted,
    this.failQueries = false,
  });

  double gapMeters;
  HealthDistancePermission permission;
  bool failQueries;
  final List<(DateTime, DateTime)> queries = [];

  @override
  bool get isSupportedPlatform => true;

  @override
  Future<HealthDistancePermission> checkPermission() async => permission;

  @override
  Future<bool> requestAuthorization() async => true;

  @override
  Future<double?> distanceMeters({
    required DateTime start,
    required DateTime end,
  }) async {
    queries.add((start, end));
    if (failQueries) return null;
    return gapMeters;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('GPS meters credit both active and total', () async {
    final walk = WalkDistanceController(odometer: GpsOdometer());
    await walk.setMode(ExploringDistanceMode.active);
    expect(walk.mode, ExploringDistanceMode.active);
    expect(walk.displayTotalMeters, walk.activeMeters);
    await walk.setMode(ExploringDistanceMode.total);
    expect(walk.mode, ExploringDistanceMode.total);
    expect(walk.displayTotalMeters, walk.totalMeters);
  });

  test(
    'weekly = max(activeWeekly, Health) credits Health − active as passive',
    () async {
      // 3.4 km active, only 3.5 km total weekly; Health says 15.4 km this week.
      SharedPreferences.setMockInitialValues({
        'walk_distance_v2_active_m': 3400.0,
        'walk_distance_v2_active_weekly_m': 3400.0,
        'walk_distance_v2_total_m': 3500.0,
        'walk_distance_v2_weekly_m': 3500.0,
        'walk_distance_v2_week_start': weekStartIso(),
        'walk_distance_v2_weekly_schema': 1,
      });

      final health = _FakeHealth(gapMeters: 15400);
      final walk = WalkDistanceController(healthService: health);
      await walk.refresh(profile: null, force: true);

      expect(walk.activeWeeklyMeters, 3400);
      expect(walk.weeklyMeters, 15400); // max(3400, 15400)
      expect(walk.totalMeters, 15400); // +11900 passive
      expect(walk.takePendingVisitGapMeters(), 11900);
      expect(health.queries.first.$1, localWeekStartMonday());
    },
  );

  test('heals over-credited weekly down to Health floor', () async {
    // Bug state: weekly 28 km from double-counted samples; Health is 15.4 km.
    SharedPreferences.setMockInitialValues({
      'walk_distance_v2_active_m': 3400.0,
      'walk_distance_v2_active_weekly_m': 3400.0,
      'walk_distance_v2_total_m': 28000.0,
      'walk_distance_v2_weekly_m': 28000.0,
      'walk_distance_v2_week_start': weekStartIso(),
      'walk_distance_v2_weekly_schema': 1,
    });

    final health = _FakeHealth(gapMeters: 15400);
    final walk = WalkDistanceController(healthService: health);
    await walk.refresh(profile: null, force: true);

    expect(walk.weeklyMeters, 15400);
    expect(walk.totalMeters, 15400); // 28000 + (15400 − 28000)
    expect(walk.takePendingVisitGapMeters(), isNull); // delta negative
  });

  test('Health below active leaves weekly at active (passive 0)', () async {
    SharedPreferences.setMockInitialValues({
      'walk_distance_v2_active_m': 5000.0,
      'walk_distance_v2_active_weekly_m': 5000.0,
      'walk_distance_v2_total_m': 5000.0,
      'walk_distance_v2_weekly_m': 5000.0,
      'walk_distance_v2_week_start': weekStartIso(),
      'walk_distance_v2_weekly_schema': 1,
    });

    final health = _FakeHealth(gapMeters: 3000);
    final walk = WalkDistanceController(healthService: health);
    await walk.refresh(profile: null, force: true);

    expect(walk.weeklyMeters, 5000);
    expect(walk.totalMeters, 5000);
    expect(walk.takePendingVisitGapMeters(), isNull);
  });

  test('iOS unknown Health permission still reconciles', () async {
    SharedPreferences.setMockInitialValues({
      'walk_distance_v2_active_m': 1000.0,
      'walk_distance_v2_active_weekly_m': 1000.0,
      'walk_distance_v2_total_m': 1000.0,
      'walk_distance_v2_weekly_m': 1000.0,
      'walk_distance_v2_week_start': weekStartIso(),
      'walk_distance_v2_weekly_schema': 1,
    });

    final health = _FakeHealth(
      gapMeters: 7000,
      permission: HealthDistancePermission.unknown,
    );
    final walk = WalkDistanceController(healthService: health);
    await walk.refresh(profile: null, force: true);

    expect(walk.weeklyMeters, 7000);
    expect(walk.takePendingVisitGapMeters(), 6000);
  });

  test('credit under 10 m updates totals but no visit badge', () async {
    SharedPreferences.setMockInitialValues({
      'walk_distance_v2_active_m': 1000.0,
      'walk_distance_v2_active_weekly_m': 1000.0,
      'walk_distance_v2_total_m': 1000.0,
      'walk_distance_v2_weekly_m': 1000.0,
      'walk_distance_v2_week_start': weekStartIso(),
      'walk_distance_v2_weekly_schema': 1,
    });

    final health = _FakeHealth(gapMeters: 1009);
    final walk = WalkDistanceController(healthService: health);
    await walk.refresh(profile: null, force: true);

    expect(walk.weeklyMeters, 1009);
    expect(walk.takePendingVisitGapMeters(), isNull);
  });

  test('failed Health query leaves weekly unchanged for retry', () async {
    SharedPreferences.setMockInitialValues({
      'walk_distance_v2_active_m': 1000.0,
      'walk_distance_v2_active_weekly_m': 1000.0,
      'walk_distance_v2_total_m': 1000.0,
      'walk_distance_v2_weekly_m': 1000.0,
      'walk_distance_v2_week_start': weekStartIso(),
      'walk_distance_v2_weekly_schema': 1,
    });

    final health = _FakeHealth(failQueries: true);
    final walk = WalkDistanceController(healthService: health);
    await walk.refresh(profile: null, force: true);
    expect(walk.weeklyMeters, 1000);

    health.failQueries = false;
    health.gapMeters = 2500;
    await walk.refresh(profile: null, force: true);
    expect(walk.weeklyMeters, 2500);
  });

  test('applyProfile does not reseed weekly from prior week', () async {
    SharedPreferences.setMockInitialValues({
      'walk_distance_v2_active_m': 5000.0,
      'walk_distance_v2_active_weekly_m': 0.0,
      'walk_distance_v2_total_m': 8000.0,
      'walk_distance_v2_weekly_m': 0.0,
      'walk_distance_v2_week_start': weekStartIso(),
      'walk_distance_v2_weekly_schema': 1,
    });

    final walk = WalkDistanceController(healthService: _FakeHealth());
    await walk.refresh(profile: null, force: true);

    final lastWeek = localWeekStartMonday(
      DateTime.now().subtract(const Duration(days: 7)),
    );
    final y = lastWeek.year.toString().padLeft(4, '0');
    final m = lastWeek.month.toString().padLeft(2, '0');
    final d = lastWeek.day.toString().padLeft(2, '0');
    walk.applyProfile(
      Profile(
        id: 1,
        displayName: 'Walker',
        username: 'walker',
        xp: 0,
        specialization: 'Paleontologist',
        yearsOfExperience: 0,
        notableDiscovery: '',
        favoriteEra: '',
        level: 1,
        achievements: const [],
        profileImage: '',
        bio: '',
        currentLocation: '',
        actualDinosaursCount: 0,
        actualFossilsCount: 0,
        actualSitesCount: 0,
        email: 'w@example.com',
        activeDistanceM: 5000,
        activeWeeklyDistanceM: 4800,
        totalDistanceM: 8000,
        weeklyDistanceM: 6000,
        distanceWeekStart: '$y-$m-$d',
      ),
    );

    expect(walk.activeWeeklyMeters, 0);
    expect(walk.weeklyMeters, 0);
    expect(walk.activeMeters, 5000);
  });

  test('schema heal zeros poisoned weekly equal to all-time', () async {
    SharedPreferences.setMockInitialValues({
      'walk_distance_v2_active_m': 5000.0,
      'walk_distance_v2_active_weekly_m': 5000.0,
      'walk_distance_v2_total_m': 5000.0,
      'walk_distance_v2_weekly_m': 5000.0,
      'walk_distance_v2_week_start': weekStartIso(),
      'walk_distance_v2_bootstrapped': true,
    });

    final walk = WalkDistanceController(
      healthService: _FakeHealth(gapMeters: 0),
    );
    await walk.refresh(profile: null, force: true);

    expect(walk.activeWeeklyMeters, 0);
    expect(walk.weeklyMeters, 0);
    expect(walk.activeMeters, 5000);
    expect(walk.totalMeters, 5000);
  });
}
