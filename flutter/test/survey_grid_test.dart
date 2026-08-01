import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/utils/survey_grid.dart';

void main() {
  test('snapToCellCenter is stable', () {
    const lat = 50.8503;
    const lon = 4.3517;
    final c1 = snapToCellCenter(lat, lon, cellSizeM: 200);
    final c2 = snapToCellCenter(c1.$1, c1.$2, cellSizeM: 200);
    expect(c1.$1, closeTo(c2.$1, 1e-9));
    expect(c1.$2, closeTo(c2.$2, 1e-9));
  });

  test('snapWidenessM steps by 200', () {
    expect(
      snapWidenessM(
        200,
        cellSizeM: 200,
        minWidenessM: 200,
        maxWidenessM: 2000,
      ),
      200,
    );
    expect(
      snapWidenessM(
        350,
        cellSizeM: 200,
        minWidenessM: 200,
        maxWidenessM: 2000,
      ),
      400,
    );
  });

  test('footprint N×N bbox', () {
    final center = snapToCellCenter(50.85, 4.35, cellSizeM: 200);
    final one = footprintForCenter(
      center.$1,
      center.$2,
      widenessM: 200,
      cellSizeM: 200,
    );
    expect(one.n, 1);
    expect(one.west < one.east, isTrue);
    expect(one.south < one.north, isTrue);

    final two = footprintForCenter(
      center.$1,
      center.$2,
      widenessM: 400,
      cellSizeM: 200,
    );
    expect(two.n, 2);
    expect(two.east - two.west, greaterThan(one.east - one.west));
  });
}
