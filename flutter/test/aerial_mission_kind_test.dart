import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/aerial_mission_kind.dart';

void main() {
  test('AerialMissionKind maps tool names and colors', () {
    expect(
      AerialMissionKind.tryParseToolName('Aerial Recon'),
      AerialMissionKind.recon,
    );
    expect(
      AerialMissionKind.tryParseToolName('Aerial Scout'),
      AerialMissionKind.scout,
    );
    expect(AerialMissionKind.tryParseToolName('Orbit Survey'), isNull);

    expect(AerialMissionKind.scout.activeRouteColor, const Color(0xFF4A4A4A));
    expect(AerialMissionKind.scout.pastRouteColor, const Color(0xFF8A8A8A));
    expect(AerialMissionKind.recon.activeRouteColor, const Color(0xFFD4AF37));

    expect(
      AerialMissionKind.fromActionKey('aerial_scout'),
      AerialMissionKind.scout,
    );
  });
}
