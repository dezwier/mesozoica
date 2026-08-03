import '../models/disguise_tool_kind.dart';
import '../models/guidance_tool_kind.dart';
import '../models/main_param_buff_kind.dart';
import '../models/tool.dart';
import '../models/tool_session.dart';
import 'game_config.dart';

/// One tool instance's [modifies_main_params], applied as owning and/or using.
class ToolModBinding {
  const ToolModBinding({
    required this.actionKey,
    required this.toolName,
    required this.mods,
    this.applyOwning = false,
    this.applyUsing = false,
    this.activeWeatherTimes,
  });

  final String actionKey;
  final String toolName;
  final ModifiesMainParams mods;
  final bool applyOwning;
  final bool applyUsing;

  /// When set, `using` mods only apply if [weatherTime] is in this list.
  final List<String>? activeWeatherTimes;

  bool usingAllowedForWeatherTime(String? weatherTime) {
    final allowed = activeWeatherTimes;
    if (allowed == null) return true;
    if (weatherTime == null) return false;
    return allowed.contains(weatherTime);
  }
}

/// Parse [modifies_main_params] from tool/session params. Never reads YAML.
ModifiesMainParams? modifiesMainParamsFromParams(Map<String, dynamic>? params) {
  final raw = params?['modifies_main_params'];
  if (raw is! Map) return null;
  final mods = ModifiesMainParams.fromYaml(Map<String, dynamic>.from(raw));
  return mods.hasAny ? mods : null;
}

List<String>? activeWeatherTimesFromParams(Map<String, dynamic>? params) {
  final raw = params?['active_weather_times'];
  if (raw is! List) return null;
  return raw.map((e) => e.toString()).toList();
}

/// Owned-card params (instance), never catalog YAML [baseParams].
Map<String, dynamic> ownedToolInstanceParams(ToolSummary tool) {
  return tool.params;
}

String? actionKeyForToolName(String name) {
  final guidance = GuidanceToolKind.tryParseToolName(name);
  if (guidance != null) return guidance.actionKey;
  final buff = MainParamBuffKind.tryParseToolName(name);
  if (buff != null) return buff.actionKey;
  final disguise = DisguiseToolKind.tryParseToolName(name);
  if (disguise != null) return disguise.actionKey;
  return null;
}

String toolNameForActionKey(String actionKey) {
  final guidance = GuidanceToolKind.tryParseActionKey(actionKey);
  if (guidance != null) return guidance.toolName;
  final buff = MainParamBuffKind.tryParseActionKey(actionKey);
  if (buff != null) return buff.toolName;
  final disguise = DisguiseToolKind.tryParseActionKey(actionKey);
  if (disguise != null) return disguise.toolName;
  return actionKey;
}

bool _toolIsOwned(ToolSummary tool) =>
    tool.isOwned || tool.ownedOccurrences.isNotEmpty;

/// Build bindings from owned catalog cards + the active session's snapshotted
/// params. YAML baselines are never consulted.
List<ToolModBinding> toolModBindingsFromInstances({
  required Iterable<ToolSummary> catalog,
  ToolSession? activeSession,
  String? activeActionKey,
  String? activeToolName,
}) {
  final bindings = <ToolModBinding>[];

  for (final tool in catalog) {
    if (!_toolIsOwned(tool)) continue;
    final actionKey = actionKeyForToolName(tool.name);
    if (actionKey == null) continue;
    var mods = modifiesMainParamsFromParams(ownedToolInstanceParams(tool));
    // Disguise cards store site-scoped `using` mods; fall back to YAML defaults
    // when an older owned instance has not been re-seeded yet.
    if (mods == null && DisguiseToolKind.matchesToolName(tool.name)) {
      if (GameConfig.isLoaded) {
        mods = modifiesMainParamsFromParams(
          GameConfig.instance.toolActions.defaultsForToolName(tool.name),
        );
      }
    }
    if (mods == null) continue;

    // Catalog cards contribute owning mods only. Active `using` comes from the
    // session snapshot below (authoritative for the card that was started).
    bindings.add(
      ToolModBinding(
        actionKey: actionKey,
        toolName: tool.name,
        mods: mods,
        applyOwning: true,
        applyUsing: false,
        activeWeatherTimes: activeWeatherTimesFromParams(
          ownedToolInstanceParams(tool),
        ),
      ),
    );
  }

  // Session snapshot is authoritative for `using` (covers restore when the
  // catalog card isn't loaded / tool pointer is null).
  if (activeSession != null) {
    final key = activeActionKey ?? activeSession.actionKey;
    final mods = modifiesMainParamsFromParams(activeSession.params);
    if (mods != null) {
      bindings.add(
        ToolModBinding(
          actionKey: key,
          toolName: activeToolName ?? toolNameForActionKey(key),
          mods: mods,
          applyOwning: false,
          applyUsing: true,
          activeWeatherTimes:
              activeWeatherTimesFromParams(activeSession.params),
        ),
      );
    }
  }

  return bindings;
}
