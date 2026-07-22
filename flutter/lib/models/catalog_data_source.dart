enum CatalogDataSource {
  archive,
  field;

  String get apiValue => name;

  static CatalogDataSource fromStored(String? value) {
    if (value == field.name) return field;
    return archive;
  }
}
