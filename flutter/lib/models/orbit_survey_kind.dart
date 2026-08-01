/// Identity for the Orbit Survey tool card.
abstract final class OrbitSurveyKind {
  static const actionKey = 'orbit_survey';
  static const toolName = 'Orbit Survey';

  static bool matchesToolName(String? name) => name == toolName;
}
