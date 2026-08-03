/// Identity for Brush Scrim / Blackout Cover disguise tools.
enum DisguiseToolKind {
  brushScrim(
    actionKey: 'brush_scrim',
    toolName: 'Brush Scrim',
  ),
  blackoutCover(
    actionKey: 'blackout_cover',
    toolName: 'Blackout Cover',
  );

  const DisguiseToolKind({
    required this.actionKey,
    required this.toolName,
  });

  final String actionKey;
  final String toolName;

  static DisguiseToolKind? tryParseToolName(String? name) {
    for (final kind in values) {
      if (kind.toolName == name) return kind;
    }
    return null;
  }

  static DisguiseToolKind? tryParseActionKey(String? key) {
    for (final kind in values) {
      if (kind.actionKey == key) return kind;
    }
    return null;
  }

  static bool matchesToolName(String? name) => tryParseToolName(name) != null;

  static bool matchesActionKey(String? key) => tryParseActionKey(key) != null;
}
