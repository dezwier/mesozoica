// Typed parser for the leveling YAML document.

import 'config_parsing.dart';

class LevelingConfig {
  const LevelingConfig({required this.skills, required this.careerTitles});

  final List<LevelingSkillConfig> skills;
  final List<String> careerTitles;

  factory LevelingConfig.fromYaml(Map<String, dynamic> yaml) {
    return LevelingConfig(
      skills: LevelingSkillConfig.listFromYaml(yaml['skills']),
      careerTitles: configAsStringList(yaml['career_titles']),
    );
  }
}

class LevelingSkillConfig {
  const LevelingSkillConfig({required this.id, required this.name});

  final String id;
  final String name;

  static List<LevelingSkillConfig> listFromYaml(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((item) => LevelingSkillConfig.fromYaml(configAsMap(item)))
        .toList();
  }

  factory LevelingSkillConfig.fromYaml(Map<String, dynamic> yaml) {
    return LevelingSkillConfig(
      id: yaml['id'] as String? ?? '',
      name: yaml['name'] as String? ?? '',
    );
  }
}
