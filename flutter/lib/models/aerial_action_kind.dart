import 'package:flutter/material.dart';

import '../config/game_config.dart';

/// Shared identity for aerial loop tools (recon, scout, …).
enum AerialActionKind {
  recon(
    actionKey: 'aerial_recon',
    toolName: 'Aerial Recon',
    timelineLabel: 'Aerial recon',
    abortLabel: 'Abort Aerial Recon',
    deployVerb: 'Deploy',
    deployedSnack: 'Aerial Recon deployed — preparing field data…',
    activeRouteColor: Color(0xFFD4AF37),
    pastRouteColor: Color(0xFFD4AF37),
  ),
  scout(
    actionKey: 'aerial_scout',
    toolName: 'Aerial Scout',
    timelineLabel: 'Aerial scout',
    abortLabel: 'Abort Aerial Scout',
    deployVerb: 'Launch',
    deployedSnack: 'Aerial Scout launched — preparing field data…',
    activeRouteColor: Color(0xFF4A4A4A),
    pastRouteColor: Color(0xFF8A8A8A),
  );

  const AerialActionKind({
    required this.actionKey,
    required this.toolName,
    required this.timelineLabel,
    required this.abortLabel,
    required this.deployVerb,
    required this.deployedSnack,
    required this.activeRouteColor,
    required this.pastRouteColor,
  });

  final String actionKey;
  final String toolName;
  final String timelineLabel;
  final String abortLabel;
  final String deployVerb;
  final String deployedSnack;
  final Color activeRouteColor;
  final Color pastRouteColor;

  int get activeRouteArgb => activeRouteColor.toARGB32();
  int get pastRouteArgb => pastRouteColor.toARGB32();

  static const aerialActionKeys = {'aerial_recon', 'aerial_scout'};

  AerialActionConfig config(GameConfig gameConfig) =>
      gameConfig.toolActions.configFor(actionKey);

  static bool isAerialActionKey(String? actionKey) =>
      actionKey != null && aerialActionKeys.contains(actionKey);

  static AerialActionKind? tryParseActionKey(String? actionKey) {
    if (actionKey == null) return null;
    for (final kind in values) {
      if (kind.actionKey == actionKey) return kind;
    }
    return null;
  }

  static AerialActionKind? tryParseToolName(String? toolName) {
    if (toolName == null) return null;
    for (final kind in values) {
      if (kind.toolName == toolName) return kind;
    }
    return null;
  }

  static AerialActionKind requireToolName(String toolName) {
    final kind = tryParseToolName(toolName);
    if (kind == null) {
      throw ArgumentError('Not an aerial tool: $toolName');
    }
    return kind;
  }

  static AerialActionKind fromActionKey(String actionKey) {
    return tryParseActionKey(actionKey) ?? recon;
  }
}
