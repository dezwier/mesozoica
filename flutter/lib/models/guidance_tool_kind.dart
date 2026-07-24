import '../config/game_config.dart';

/// Shared identity for site-guidance tools (compass, proximity, navigator).
enum GuidanceToolKind {
  geoCompass(
    actionKey: 'geo_compass',
    toolName: 'Geo Compass',
    showNeedle: true,
    showDistance: false,
    hasDiscoveryBoost: true,
  ),
  proximityScanner(
    actionKey: 'proximity_scanner',
    toolName: 'Proximity Scanner',
    showNeedle: false,
    showDistance: true,
    hasDiscoveryBoost: false,
  ),
  siteNavigator(
    actionKey: 'site_navigator',
    toolName: 'Site Navigator',
    showNeedle: true,
    showDistance: true,
    hasDiscoveryBoost: true,
  );

  const GuidanceToolKind({
    required this.actionKey,
    required this.toolName,
    required this.showNeedle,
    required this.showDistance,
    required this.hasDiscoveryBoost,
  });

  final String actionKey;
  final String toolName;
  final bool showNeedle;
  final bool showDistance;
  final bool hasDiscoveryBoost;

  GuidanceActionConfig config(GameConfig gameConfig) =>
      gameConfig.toolActions.guidanceConfigFor(actionKey);

  static GuidanceToolKind? tryParseActionKey(String? actionKey) {
    if (actionKey == null) return null;
    for (final kind in values) {
      if (kind.actionKey == actionKey) return kind;
    }
    return null;
  }

  static GuidanceToolKind? tryParseToolName(String? toolName) {
    if (toolName == null) return null;
    for (final kind in values) {
      if (kind.toolName == toolName) return kind;
    }
    return null;
  }

  static GuidanceToolKind requireToolName(String toolName) {
    final kind = tryParseToolName(toolName);
    if (kind == null) {
      throw ArgumentError('Not a guidance tool: $toolName');
    }
    return kind;
  }
}
