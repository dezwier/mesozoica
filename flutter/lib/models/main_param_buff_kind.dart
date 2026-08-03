/// Identity for timed global main-param buff tools.
class MainParamBuffKind {
  const MainParamBuffKind({
    required this.actionKey,
    required this.toolName,
    required this.hudLabel,
  });

  final String actionKey;
  final String toolName;
  final String hudLabel;

  static const ridgeGlass = MainParamBuffKind(
    actionKey: 'ridge_glass',
    toolName: 'Ridge Glass',
    hudLabel: 'SCOUT',
  );

  static const expeditionDrivetrain = MainParamBuffKind(
    actionKey: 'expedition_drivetrain',
    toolName: 'Expedition Drivetrain',
    hudLabel: 'RIDE',
  );

  static const nocturneLens = MainParamBuffKind(
    actionKey: 'nocturne_lens',
    toolName: 'Nocturne Lens',
    hudLabel: 'NIGHT',
  );

  static const all = <MainParamBuffKind>[
    ridgeGlass,
    expeditionDrivetrain,
    nocturneLens,
  ];

  static const actionKeys = <String>[
    'ridge_glass',
    'expedition_drivetrain',
    'nocturne_lens',
  ];

  static MainParamBuffKind? tryParseToolName(String? name) {
    if (name == null) return null;
    for (final kind in all) {
      if (kind.toolName == name) return kind;
    }
    return null;
  }

  static MainParamBuffKind? tryParseActionKey(String? key) {
    if (key == null) return null;
    for (final kind in all) {
      if (kind.actionKey == key) return kind;
    }
    return null;
  }

  static bool matchesToolName(String? name) => tryParseToolName(name) != null;

  static bool matchesActionKey(String? key) => tryParseActionKey(key) != null;
}

/// Back-compat aliases.
abstract final class RidgeGlassKind {
  static const actionKey = 'ridge_glass';
  static const toolName = 'Ridge Glass';

  static bool matchesToolName(String? name) => name == toolName;

  static bool matchesActionKey(String? key) => key == actionKey;
}

abstract final class ExpeditionDrivetrainKind {
  static const actionKey = 'expedition_drivetrain';
  static const toolName = 'Expedition Drivetrain';

  static bool matchesToolName(String? name) => name == toolName;

  static bool matchesActionKey(String? key) => key == actionKey;
}

abstract final class NocturneLensKind {
  static const actionKey = 'nocturne_lens';
  static const toolName = 'Nocturne Lens';

  static bool matchesToolName(String? name) => name == toolName;

  static bool matchesActionKey(String? key) => key == actionKey;
}
