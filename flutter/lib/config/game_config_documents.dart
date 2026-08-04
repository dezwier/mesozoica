/// Control board document ids and their bundled asset filenames.
///
/// Must mirror `DOCUMENT_FILES` in `backend/app/core/game_config.py` exactly —
/// the ids are the keys the config API serves and the cache stores.
const Map<String, String> kGameConfigDocumentFiles = <String, String>{
  'site_generation': 'site_generation.yaml',
  'site_discovery': '01_site_discovery.yaml',
  'site_stewardship': '02_site_stewardship.yaml',
  'site_clearing': '03_site_clearing.yaml',
  'fossil_detection': '04_fossil_detection.yaml',
  'fossil_excavation': '05_fossil_excavation.yaml',
  'fossil_transport': '06_fossil_transport.yaml',
  'fossil_curation': '07_fossil_curation.yaml',
  'fossil_preparation': '08_fossil_preparation.yaml',
  'fossil_analysis': '09_fossil_analysis.yaml',
  'dinosaur_modelling': '10_dinosaur_modelling.yaml',
  'dinosaur_mounting': '11_dinosaur_mounting.yaml',
  'academic_publishing': '12_academic_publishing.yaml',
  'tool_actions': 'tool_actions.yaml',
  'period_colors': 'period_colors.yaml',
  'rock_type_colors': 'rock_type_colors.yaml',
  'leveling': 'leveling.yaml',
};

/// Document ids in load order.
final List<String> kGameConfigDocumentIds =
    List<String>.unmodifiable(kGameConfigDocumentFiles.keys);
