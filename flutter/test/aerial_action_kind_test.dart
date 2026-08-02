import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/aerial_action_kind.dart';

void main() {
  test('AerialActionKind maps tool names and colors', () {
    expect(
      AerialActionKind.tryParseToolName('Aerial Recon'),
      AerialActionKind.recon,
    );
    expect(
      AerialActionKind.tryParseToolName('Aerial Scout'),
      AerialActionKind.scout,
    );
    expect(AerialActionKind.tryParseToolName('Orbit Survey'), isNull);

    expect(AerialActionKind.scout.activeRouteColor, const Color(0xFF4A4A4A));
    expect(AerialActionKind.scout.pastRouteColor, const Color(0xFF8A8A8A));
    expect(AerialActionKind.recon.activeRouteColor, const Color(0xFFD4AF37));

    expect(
      AerialActionKind.fromActionKey('aerial_scout'),
      AerialActionKind.scout,
    );
  });
}
