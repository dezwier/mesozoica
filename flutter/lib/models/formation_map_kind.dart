/// Identity for the Formation Map tool card.
abstract final class FormationMapKind {
  static const actionKey = 'formation_map';
  static const toolName = 'Formation Map';

  static bool matchesToolName(String? name) => name == toolName;
}
