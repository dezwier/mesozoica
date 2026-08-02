import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/game_config.dart';
import '../../controllers/aerial_mission_controller.dart';
import '../../models/aerial_mission_kind.dart';
import '../../services/tool_service.dart';
import '../tools/aerial_mission_actions.dart';
import 'active_tool_hud_shell.dart';
import 'vintage_guidance_compass.dart';

/// Compact vintage map chip for focused / active aerial missions (draggable).
///
/// Tap (not drag) follows the flight; ABORT cancels an active mission.
class AerialMissionHud extends StatelessWidget {
  const AerialMissionHud({super.key});

  @override
  Widget build(BuildContext context) {
    final aerial = context.watch<AerialMissionController>();
    final mission = aerial.hudMission;
    if (mission == null) return const SizedBox.shrink();

    final kind = AerialMissionKind.fromActionKey(mission.actionKey);
    final active = mission.isActive;

    return ActiveToolHudShell(
      icon: _AerialHudIcon(kind: kind, size: 26),
      remainingListenable: aerial.remainingListenable,
      stopLabel: active ? 'ABORT' : 'CLOSE',
      onStop: () {
        if (active) {
          AerialMissionActions.confirmAbort(context, mission);
        } else {
          context.read<AerialMissionController>().clearFocus();
        }
      },
      onTap: () => context.read<AerialMissionController>().focusMission(mission),
      body: ListenableBuilder(
        listenable: aerial.progressTickListenable,
        builder: (context, _) => _AerialHudBody(mission: mission, kind: kind),
      ),
    );
  }
}

class _AerialHudBody extends StatelessWidget {
  const _AerialHudBody({
    required this.mission,
    required this.kind,
  });

  final AerialMission mission;
  final AerialMissionKind kind;

  @override
  Widget build(BuildContext context) {
    final cfg = GameConfig.instance.toolActions.configFor(mission.actionKey);
    final speed = mission.flightSpeedKmh ?? cfg.flightSpeedKmh;
    final durationMin = _minutesFromFlightSeconds(mission.flightDurationS);
    final chance = mission.discoveryChance ?? cfg.discoveryChance;
    final visibility = mission.discoveryDistanceM ?? cfg.discoveryDistanceM;

    final status = mission.isEnsuring
        ? 'PREP'
        : mission.isFlying
            ? 'LIVE'
            : mission.status.toUpperCase();
    final length = mission.routeLengthKm == mission.routeLengthKm.roundToDouble()
        ? mission.routeLengthKm.toStringAsFixed(0)
        : mission.routeLengthKm.toStringAsFixed(1);

    final muted = VintageInstrumentStyle.mono.copyWith(
      fontSize: 9,
      letterSpacing: 0.6,
      color: VintageInstrumentStyle.brassMuted,
      height: 1.25,
    );
    final value = VintageInstrumentStyle.mono.copyWith(
      fontSize: 9,
      letterSpacing: 0.5,
      color: VintageInstrumentStyle.brassText,
      height: 1.25,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${kind == AerialMissionKind.scout ? 'SCOUT' : 'RECON'} · $status · '
          '$length KM · ${mission.discoveredSiteCount} SITES',
          style: muted,
        ),
        const SizedBox(height: 5),
        Text(
          '${_formatKmh(speed)} · ${_formatDuration(durationMin)} · '
          '${_formatChance(chance)} · ${_formatMeters(visibility)}',
          style: value,
        ),
        Text(
          'SPEED · DURATION · CHANCE · VIS',
          style: muted.copyWith(fontSize: 8, letterSpacing: 0.8),
        ),
      ],
    );
  }

  static int _minutesFromFlightSeconds(int seconds) {
    if (seconds <= 0) return 0;
    final minutes = (seconds / 60).round();
    return minutes < 1 ? 1 : minutes;
  }

  static String _formatKmh(double v) {
    final label = v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(1);
    return '$label KM/H';
  }

  static String _formatDuration(int minutes) {
    if (minutes <= 0) return '—';
    if (minutes < 60) return '$minutes MIN';
    final hours = minutes ~/ 60;
    final rem = minutes % 60;
    if (rem == 0) return hours == 1 ? '1 H' : '$hours H';
    return '${hours}H ${rem}M';
  }

  static String _formatChance(double v) {
    final pct = v * 100;
    final label = pct == pct.roundToDouble()
        ? pct.toStringAsFixed(0)
        : pct.toStringAsFixed(1);
    return '$label%';
  }

  static String _formatMeters(double v) {
    return '${v.round()}M';
  }
}

class _AerialHudIcon extends StatelessWidget {
  const _AerialHudIcon({required this.kind, required this.size});

  final AerialMissionKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AerialHudIconPainter(
          accent: kind.activeRouteColor,
        ),
      ),
    );
  }
}

class _AerialHudIconPainter extends CustomPainter {
  _AerialHudIconPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.38;
    final face = Paint()..color = const Color(0xFF1A1208);
    final rim = Paint()
      ..color = VintageInstrumentStyle.brassRim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(center, r, face);
    canvas.drawCircle(center, r, rim);

    final wing = Paint()
      ..color = accent.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(center.dx - r * 0.55, center.dy)
      ..lineTo(center.dx + r * 0.15, center.dy - r * 0.45)
      ..lineTo(center.dx + r * 0.55, center.dy)
      ..lineTo(center.dx + r * 0.15, center.dy + r * 0.45)
      ..close();
    canvas.drawPath(path, wing);

    final fuselage = Paint()
      ..color = VintageInstrumentStyle.brassText
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx - r * 0.35, center.dy),
      Offset(center.dx + r * 0.45, center.dy),
      fuselage,
    );
  }

  @override
  bool shouldRepaint(covariant _AerialHudIconPainter oldDelegate) =>
      oldDelegate.accent != accent;
}
