// Typed modifier models shared by skill and tool-action documents.

import 'config_parsing.dart';

class LevelModifierEntry {
  const LevelModifierEntry({
    required this.level,
    required this.op,
    required this.value,
  });

  final int level;
  final String op;
  final double value;

  static Map<String, List<LevelModifierEntry>> mapFromYaml(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, List<LevelModifierEntry>>{};
    for (final entry in raw.entries) {
      final list = <LevelModifierEntry>[];
      if (entry.value is List) {
        for (final item in entry.value as List) {
          if (item is Map) {
            list.add(
              LevelModifierEntry(
                level: configAsInt(item['level'], 1),
                op: item['op'] as String? ?? 'add',
                value: configAsDouble(item['value'], 0),
              ),
            );
          }
        }
      }
      out[entry.key.toString()] = list;
    }
    return out;
  }
}

class ParamModifier {
  const ParamModifier({required this.op, required this.value});

  final String op;
  final double value;

  factory ParamModifier.fromYaml(Map<String, dynamic> yaml) {
    return ParamModifier(
      op: yaml['op'] as String? ?? 'replace',
      value: configAsDouble(yaml['value'], 0),
    );
  }
}

/// Parse ambient modifiers: param → key (period or weather type) → mods.
Map<String, Map<String, List<ParamModifier>>> ambientModifiersFromYaml(
  Object? raw,
) {
  if (raw is! Map) return const {};
  final out = <String, Map<String, List<ParamModifier>>>{};
  for (final paramEntry in raw.entries) {
    final keyed = <String, List<ParamModifier>>{};
    final keyedRaw = paramEntry.value;
    if (keyedRaw is Map) {
      for (final keyEntry in keyedRaw.entries) {
        final list = <ParamModifier>[];
        if (keyEntry.value is List) {
          for (final item in keyEntry.value as List) {
            if (item is Map) {
              list.add(ParamModifier.fromYaml(Map<String, dynamic>.from(item)));
            }
          }
        }
        var key = keyEntry.key.toString();
        if (key == 'sunny') key = 'clear';
        keyed[key] = list;
      }
    }
    out[paramEntry.key.toString()] = keyed;
  }
  return out;
}

/// Back-compat alias.
Map<String, Map<String, List<ParamModifier>>> weatherTimeModifiersFromYaml(
  Object? raw,
) => ambientModifiersFromYaml(raw);

class ModifiesMainParams {
  const ModifiesMainParams({this.owning = const {}, this.using = const {}});

  /// Passiveive: skill_id → param → modifier, while owned.
  final Map<String, Map<String, ParamModifier>> owning;

  /// Active: skill_id → param → modifier, while tool session is in use.
  final Map<String, Map<String, ParamModifier>> using;

  bool get hasAny => owning.isNotEmpty || using.isNotEmpty;

  bool affectsSkill(String skillId) =>
      owning.containsKey(skillId) || using.containsKey(skillId);

  Map<String, ParamModifier> paramsFor(String when, String skillId) {
    final bucket = when == 'owning' ? owning : using;
    return bucket[skillId] ?? const {};
  }

  static bool _looksLikeParamModifier(Object? value) {
    if (value is! Map) return false;
    return value.containsKey('op') && value.containsKey('value');
  }

  static bool _looksLikeParamMap(Object? value) {
    if (value is! Map) return false;
    if (value.isEmpty) return true;
    return value.values.every(_looksLikeParamModifier);
  }

  static Map<String, ParamModifier> _parseParamMap(Object? raw) {
    final map = configAsMap(raw);
    final out = <String, ParamModifier>{};
    for (final entry in map.entries) {
      if (entry.value is Map) {
        out[entry.key] = ParamModifier.fromYaml(configAsMap(entry.value));
      }
    }
    return out;
  }

  static Map<String, Map<String, ParamModifier>> _parseSkillMap(Object? raw) {
    final map = configAsMap(raw);
    final out = <String, Map<String, ParamModifier>>{};
    for (final entry in map.entries) {
      out[entry.key] = _parseParamMap(entry.value);
    }
    return out;
  }

  factory ModifiesMainParams.fromYaml(Map<String, dynamic> yaml) {
    final skill = yaml['skill'] as String?;
    Object? owningRaw = yaml['owning'];
    Object? usingRaw = yaml['using'];

    // Legacy: when + params
    if (owningRaw == null && usingRaw == null && yaml['params'] != null) {
      final whenRaw =
          (yaml['when'] as String?)?.trim().toLowerCase() ?? 'using';
      if (whenRaw == 'owning') {
        owningRaw = yaml['params'];
      } else {
        usingRaw = yaml['params'];
      }
    }

    // Single-skill shorthand: owning/using are param maps.
    if (skill != null) {
      if (_looksLikeParamMap(owningRaw)) {
        owningRaw = {skill: owningRaw};
      }
      if (_looksLikeParamMap(usingRaw)) {
        usingRaw = {skill: usingRaw};
      }
    }

    return ModifiesMainParams(
      owning: _parseSkillMap(owningRaw),
      using: _parseSkillMap(usingRaw),
    );
  }
}

class SkillStubConfig {
  const SkillStubConfig({
    required this.skillId,
    required this.enabled,
    required this.mainParams,
    required this.levelModifiers,
    this.weatherTimeModifiers = const {},
    this.weatherTypeModifiers = const {},
  });

  final String skillId;
  final bool enabled;
  final Map<String, dynamic> mainParams;
  final Map<String, List<LevelModifierEntry>> levelModifiers;
  final Map<String, Map<String, List<ParamModifier>>> weatherTimeModifiers;
  final Map<String, Map<String, List<ParamModifier>>> weatherTypeModifiers;

  bool get hasMainParams => mainParams.isNotEmpty;

  factory SkillStubConfig.fromYaml(Map<String, dynamic> yaml) {
    return SkillStubConfig(
      skillId: yaml['skill_id'] as String? ?? '',
      enabled: yaml['enabled'] == true,
      mainParams: configAsMap(yaml['main_params']),
      levelModifiers: LevelModifierEntry.mapFromYaml(yaml['level_modifiers']),
      weatherTimeModifiers: ambientModifiersFromYaml(
        yaml['weather_time_modifiers'],
      ),
      weatherTypeModifiers: ambientModifiersFromYaml(
        yaml['weather_type_modifiers'],
      ),
    );
  }
}
