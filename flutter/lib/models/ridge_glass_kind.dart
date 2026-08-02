/// Identity for the Ridge Glass tool card.
abstract final class RidgeGlassKind {
  static const actionKey = 'ridge_glass';
  static const toolName = 'Ridge Glass';

  static bool matchesToolName(String? name) => name == toolName;

  static bool matchesActionKey(String? key) => key == actionKey;
}
