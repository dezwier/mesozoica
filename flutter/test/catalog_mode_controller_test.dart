import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/controllers/catalog_mode_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('initialize defaults to archive', () async {
    final controller = CatalogModeController();
    await controller.initialize();

    expect(controller.dataSource, CatalogDataSource.archive);
    expect(controller.isArchive, isTrue);
    expect(controller.isField, isFalse);
  });

  test('initialize restores persisted field mode', () async {
    SharedPreferences.setMockInitialValues({
      'catalog_data_source': 'field',
    });

    final controller = CatalogModeController();
    await controller.initialize();

    expect(controller.dataSource, CatalogDataSource.field);
  });

  test('setDataSource persists choice', () async {
    final controller = CatalogModeController();
    await controller.initialize();

    await controller.setDataSource(CatalogDataSource.field);

    expect(controller.dataSource, CatalogDataSource.field);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('catalog_data_source'), 'field');
  });

  test('toggle switches between archive and field', () async {
    final controller = CatalogModeController();
    await controller.initialize();

    await controller.toggle();
    expect(controller.dataSource, CatalogDataSource.field);

    await controller.toggle();
    expect(controller.dataSource, CatalogDataSource.archive);
  });
}
