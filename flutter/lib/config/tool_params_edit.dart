import 'game_config.dart';
import 'tool_instance_params.dart';

/// Shared admin-edit helpers for tool instance params (all tool cards).
abstract final class ToolParamsEdit {
  ToolParamsEdit._();

  static const _skipTopLevel = {
    'stats_explanation',
    'modifies_main_params',
  };

  /// Deep-merge YAML defaults under instance params (instance wins at leaves).
  static Map<String, dynamic> mergeDefaults(
    Map<String, dynamic> defaults,
    Map<String, dynamic> instance,
  ) {
    if (defaults.isEmpty) return _deepCopy(instance);
    if (instance.isEmpty) return _deepCopy(defaults);
    final out = _deepCopy(defaults);
    _deepMergeInto(out, instance);
    return out;
  }

  /// Keep legacy top-level `discovery_chance` in sync with using/replace impact.
  static Map<String, dynamic> syncLegacyDiscoveryChance(
    Map<String, dynamic> params,
  ) {
    final mods = modifiesMainParamsFromParams(params);
    final mod = mods?.paramsFor('using', 'site_discovery')['discovery_chance'];
    if (mod == null || mod.op != 'replace') return params;
    final out = _deepCopy(params);
    out['discovery_chance'] = mod.value;
    return out;
  }

  /// Editable dotted paths for every `{op,value}` impact entry.
  static List<String> impactEditPaths(Map<String, dynamic> params) {
    final mods = modifiesMainParamsFromParams(params);
    if (mods == null) return const [];
    final out = <String>[];
    void walk(
      String when,
      Map<String, Map<String, ParamModifier>> bucket,
    ) {
      for (final skillEntry in bucket.entries) {
        for (final paramEntry in skillEntry.value.entries) {
          final base =
              'modifies_main_params.$when.${skillEntry.key}.${paramEntry.key}';
          out.add('$base.op');
          out.add('$base.value');
        }
      }
    }

    walk('owning', mods.owning);
    walk('using', mods.using);
    return out;
  }

  static Map<String, String> impactEditLabels(List<String> paths) {
    final out = <String, String>{};
    for (final path in paths) {
      final parts = path.split('.');
      // modifies_main_params.{when}.{skill}.{param}.{op|value}
      if (parts.length < 5) continue;
      final when = _titleCase(parts[1]);
      final skill = _humanizeKey(parts[2]);
      final param = _paramLabel(parts[3]);
      final leaf = parts[4];
      out[path] = leaf == 'op'
          ? '$when · $skill · $param (op)'
          : '$when · $skill · $param';
    }
    return out;
  }

  /// Tool-specific knobs + all impact paths (deduped, impacts last).
  static List<String> editableKeys({
    required List<String> toolKeys,
    required Map<String, dynamic> params,
  }) {
    final impactPaths = impactEditPaths(params);
    final impactSet = impactPaths.toSet();
    final out = <String>[
      for (final key in toolKeys)
        if (!_skipTopLevel.contains(key) && !impactSet.contains(key)) key,
      ...impactPaths,
    ];
    return out;
  }

  static Map<String, String> editableLabels({
    required List<String> keys,
    Map<String, String> toolLabels = const {},
  }) {
    final impactLabels = impactEditLabels(keys);
    return {
      for (final key in keys)
        key: toolLabels[key] ??
            impactLabels[key] ??
            _humanizeKey(key.contains('.') ? key.split('.').last : key),
    };
  }

  static String _paramLabel(String key) {
    // Prefer shared labels when available.
    const known = <String, String>{
      'visibility_distance_m': 'Visibility distance',
      'discovery_chance': 'Discovery chance',
      'max_discovery_speed_kmh': 'Max discovery speed',
      'dino_accuracy': 'Dinosaur accuracy',
      'fossil_accuracy': 'Fossil accuracy',
      'completeness_accuracy': 'Completeness accuracy',
      'quality_accuracy': 'Quality accuracy',
      'depth_accuracy': 'Depth accuracy',
    };
    return known[key] ?? _humanizeKey(key);
  }

  static String _humanizeKey(String key) {
    return key
        .split('_')
        .where((p) => p.isNotEmpty)
        .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
        .join(' ');
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  static Map<String, dynamic> _deepCopy(Map<String, dynamic> source) {
    final out = <String, dynamic>{};
    for (final entry in source.entries) {
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        out[entry.key] = _deepCopy(value);
      } else if (value is Map) {
        out[entry.key] = _deepCopy(Map<String, dynamic>.from(value));
      } else if (value is List) {
        out[entry.key] = [
          for (final item in value)
            if (item is Map<String, dynamic>)
              _deepCopy(item)
            else if (item is Map)
              _deepCopy(Map<String, dynamic>.from(item))
            else
              item,
        ];
      } else {
        out[entry.key] = value;
      }
    }
    return out;
  }

  static void _deepMergeInto(
    Map<String, dynamic> target,
    Map<String, dynamic> overlay,
  ) {
    for (final entry in overlay.entries) {
      final key = entry.key;
      final next = entry.value;
      final prev = target[key];
      if (prev is Map && next is Map) {
        final merged = prev is Map<String, dynamic>
            ? prev
            : Map<String, dynamic>.from(prev);
        _deepMergeInto(
          merged,
          next is Map<String, dynamic>
              ? next
              : Map<String, dynamic>.from(next),
        );
        target[key] = merged;
      } else if (next is Map<String, dynamic>) {
        target[key] = _deepCopy(next);
      } else if (next is Map) {
        target[key] = _deepCopy(Map<String, dynamic>.from(next));
      } else {
        target[key] = next;
      }
    }
  }
}
