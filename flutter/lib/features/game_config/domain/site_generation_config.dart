// Typed parser for the site_generation YAML document.

import 'config_parsing.dart';

class SiteGenerationConfig {
  const SiteGenerationConfig({required this.cellSizeM, required this.client});

  /// Density square size from YAML `lazy.cell_size_m` (walk ensure cell).
  final double cellSizeM;
  final SiteGenerationClientConfig client;

  factory SiteGenerationConfig.fromYaml(Map<String, dynamic> yaml) {
    final lazy = configAsMap(yaml['lazy']);
    return SiteGenerationConfig(
      cellSizeM: configAsDouble(lazy['cell_size_m'], 500.0),
      client: SiteGenerationClientConfig.fromYaml(configAsMap(yaml['client'])),
    );
  }
}

class SiteGenerationClientConfig {
  const SiteGenerationClientConfig({required this.nearbyRadiusKm});

  final double nearbyRadiusKm;

  factory SiteGenerationClientConfig.fromYaml(Map<String, dynamic> yaml) {
    return SiteGenerationClientConfig(
      nearbyRadiusKm: configAsDouble(yaml['nearby_radius_km'], 1.0),
    );
  }
}
