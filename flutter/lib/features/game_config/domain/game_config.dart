import 'package:yaml/yaml.dart';

import 'field_survey_config.dart';
import 'leveling_config.dart';
import 'palette_config.dart';
import 'site_generation_config.dart';
import 'tool_actions_config.dart';

export 'field_survey_config.dart';
export 'leveling_config.dart';
export 'palette_config.dart';
export 'site_generation_config.dart';
export 'tool_actions_config.dart';

/// Shared game-mechanics control board (YAML under assets/game_config/).
///
/// Source of truth lives at `backend/app/game_config/` and is linked into
/// Flutter assets. Call [GameConfig.load] once in `main()` before `runApp`.
class GameConfig {
  GameConfig({
    required this.siteGeneration,
    required this.fieldSurvey,
    required this.boneQuarry,
    required this.scienceHall,
    required this.toolActions,
    required this.periodColors,
    required this.rockTypeColors,
    required this.leveling,
  });

  final SiteGenerationConfig siteGeneration;
  final FieldSurveyConfig fieldSurvey;
  final SkillStubConfig boneQuarry;
  final SkillStubConfig scienceHall;
  final ToolActionsConfig toolActions;
  final PeriodColorsConfig periodColors;
  final RockTypeColorsConfig rockTypeColors;
  final LevelingConfig leveling;

  /// Back-compat aliases for call sites during migration.
  FieldSurveyConfig get siteDiscovery => fieldSurvey;
  FieldSurveyConfig get siteStewardship => fieldSurvey;
  FieldSurveyConfig get fossilGeneration => fieldSurvey;
  SkillStubConfig get fossilDetection => boneQuarry;

  Object? skillDomain(String skillId) {
    switch (skillId) {
      case 'field_survey':
      case 'site_discovery':
      case 'site_stewardship':
      case 'site_clearing':
        return fieldSurvey;
      case 'bone_quarry':
      case 'fossil_detection':
      case 'fossil_excavation':
      case 'fossil_transport':
      case 'fossil_curation':
      case 'fossil_discovery':
        return boneQuarry;
      case 'science_hall':
      case 'fossil_preparation':
      case 'fossil_analysis':
      case 'dinosaur_modelling':
      case 'dinosaur_mounting':
      case 'academic_publishing':
        return scienceHall;
      default:
        return null;
    }
  }

  static GameConfig? _instance;

  /// Loaded singleton. Throws if [load] / [loadFromYamlStrings] was not called.
  static GameConfig get instance {
    final value = _instance;
    if (value == null) {
      throw StateError('GameConfig.load() must be called before use');
    }
    return value;
  }

  static bool get isLoaded => _instance != null;

  /// Replace the singleton (tests).
  static void debugSetInstance(GameConfig config) {
    _instance = config;
  }

  static void debugReset() {
    _instance = null;
  }

  /// Parse domain YAML strings (also used by unit tests).
  static GameConfig loadFromYamlStrings({
    required String siteGenerationYaml,
    required String fieldSurveyYaml,
    required String boneQuarryYaml,
    required String scienceHallYaml,
    required String toolActionsYaml,
    required String periodColorsYaml,
    required String rockTypeColorsYaml,
    required String levelingYaml,
  }) {
    final config = fromDocuments(<String, dynamic>{
      'site_generation': loadYaml(siteGenerationYaml),
      'field_survey': loadYaml(fieldSurveyYaml),
      'bone_quarry': loadYaml(boneQuarryYaml),
      'science_hall': loadYaml(scienceHallYaml),
      'tool_actions': loadYaml(toolActionsYaml),
      'period_colors': loadYaml(periodColorsYaml),
      'rock_type_colors': loadYaml(rockTypeColorsYaml),
      'leveling': loadYaml(levelingYaml),
    });
    _instance = config;
    return config;
  }

  /// Build from raw document maps keyed by document id.
  ///
  /// Accepts either YAML-decoded (`YamlMap`) or JSON-decoded (`Map`) values —
  /// every `fromYaml` factory below duck-types on `Map` / `List`. This is the
  /// shared seam for the bundled assets, the local cache, and the config API.
  /// Does not set the singleton.
  static GameConfig fromDocuments(Map<String, dynamic> documents) {
    Map<String, dynamic> doc(String id) {
      if (!documents.containsKey(id)) {
        throw FormatException('Missing game config document: $id');
      }
      return _asMap(documents[id]);
    }

    return GameConfig(
      siteGeneration: SiteGenerationConfig.fromYaml(doc('site_generation')),
      fieldSurvey: FieldSurveyConfig.fromYaml(doc('field_survey')),
      boneQuarry: SkillStubConfig.fromYaml(doc('bone_quarry')),
      scienceHall: SkillStubConfig.fromYaml(doc('science_hall')),
      toolActions: ToolActionsConfig.fromYaml(doc('tool_actions')),
      periodColors: PeriodColorsConfig.fromYaml(doc('period_colors')),
      rockTypeColors: RockTypeColorsConfig.fromYaml(doc('rock_type_colors')),
      leveling: LevelingConfig.fromYaml(doc('leveling')),
    );
  }

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    throw FormatException('Expected YAML mapping, got ${raw.runtimeType}');
  }
}
