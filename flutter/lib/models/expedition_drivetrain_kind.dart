/// Identity for the Expedition Drivetrain tool card.
abstract final class ExpeditionDrivetrainKind {
  static const actionKey = 'expedition_drivetrain';
  static const toolName = 'Expedition Drivetrain';

  static bool matchesToolName(String? name) => name == toolName;

  static bool matchesActionKey(String? key) => key == actionKey;
}
