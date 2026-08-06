import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/utils/survey_grid.dart';

void main() {
  test('snapToCellCenter is stable', () {
    const lat = 50.8503;
    const lon = 4.3517;
    final c1 = snapToCellCenter(lat, lon, cellSizeM: 500);
    final c2 = snapToCellCenter(c1.$1, c1.$2, cellSizeM: 500);
    expect(c1.$1, closeTo(c2.$1, 1e-9));
    expect(c1.$2, closeTo(c2.$2, 1e-9));
  });

  test('snapWidenessM steps by 500', () {
    expect(
      snapWidenessM(500, cellSizeM: 500, minWidenessM: 500, maxWidenessM: 2000),
      500,
    );
    expect(
      snapWidenessM(750, cellSizeM: 500, minWidenessM: 500, maxWidenessM: 2000),
      1000,
    );
  });

  test('footprint N×N bbox on density grid', () {
    final center = snapToCellCenter(50.85, 4.35, cellSizeM: 500);
    final one = footprintForCenter(
      center.$1,
      center.$2,
      widenessM: 500,
      cellSizeM: 500,
    );
    expect(one.n, 1);
    expect(one.cellCenters(), hasLength(1));
    expect(one.west < one.east, isTrue);
    expect(one.south < one.north, isTrue);

    final two = footprintForCenter(
      center.$1,
      center.$2,
      widenessM: 1000,
      cellSizeM: 500,
    );
    expect(two.n, 2);
    expect(two.cellCenters(), hasLength(4));
    expect(two.east - two.west, greaterThan(one.east - one.west));
  });
}
