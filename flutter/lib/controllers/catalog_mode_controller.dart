import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CatalogDataSource {
  archive,
  field;

  String get apiValue => name;

  static CatalogDataSource fromStored(String? value) {
    if (value == field.name) return field;
    return archive;
  }
}

class CatalogModeController extends ChangeNotifier {
  static const _storageKey = 'catalog_data_source';

  CatalogDataSource _dataSource = CatalogDataSource.archive;

  CatalogDataSource get dataSource => _dataSource;

  bool get isArchive => _dataSource == CatalogDataSource.archive;

  bool get isField => _dataSource == CatalogDataSource.field;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _dataSource = CatalogDataSource.fromStored(prefs.getString(_storageKey));
    notifyListeners();
  }

  Future<void> setDataSource(CatalogDataSource source) async {
    if (_dataSource == source) return;
    _dataSource = source;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, source.name);
  }

  Future<void> toggle() async {
    await setDataSource(
      isArchive ? CatalogDataSource.field : CatalogDataSource.archive,
    );
  }
}
