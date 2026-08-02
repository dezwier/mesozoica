/// Identity for the Terrain Echo tool card.
abstract final class TerrainEchoKind {
  static const actionKey = 'terrain_echo';
  static const toolName = 'Terrain Echo';

  static bool matchesToolName(String? name) => name == toolName;
}
