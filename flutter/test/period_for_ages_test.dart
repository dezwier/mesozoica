import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/site.dart';
import 'package:mesozoica/utils/period_for_ages.dart';

void main() {
  test('periodForAges maps midpoint to mesozoic periods', () {
    expect(periodForAges(220, 230), 'triassic');
    expect(periodForAges(160, 180), 'jurassic');
    expect(periodForAges(72, 84), 'cretaceous');
    expect(periodForAges(null, 100), 'cretaceous');
    expect(periodForAges(50, null), null);
    expect(periodForAges(null, null), isNull);
  });

  test(
    'SiteSummary.displayPeriod infers period from ages when site type missing',
    () {
      const site = SiteSummary(siteId: 1, minAgeMa: 72, maxAgeMa: 84);

      expect(site.effectivePeriod, 'cretaceous');
      expect(site.displayPeriod, 'Cretaceous, 72 – 84 Ma');
    },
  );
}
