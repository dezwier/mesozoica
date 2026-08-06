/// Control board document ids and their bundled asset filenames.
///
/// Must mirror `DOCUMENT_FILES` in `backend/app/core/game_config.py` exactly —
/// the ids are the keys the config API serves and the cache stores.
const Map<String, String> kGameConfigDocumentFiles = <String, String>{
  'site_generation': 'site_generation.yaml',
  'field_survey': '01_field_survey.yaml',
  'bone_quarry': '02_bone_quarry.yaml',
  'science_hall': '03_science_hall.yaml',
  'tool_actions': 'tool_actions.yaml',
  'period_colors': 'period_colors.yaml',
  'rock_type_colors': 'rock_type_colors.yaml',
  'leveling': 'leveling.yaml',
};

/// Document ids in load order.
final List<String> kGameConfigDocumentIds = List<String>.unmodifiable(
  kGameConfigDocumentFiles.keys,
);
