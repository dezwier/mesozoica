import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/terrain_echo_controller.dart';
import 'active_tool_hud_shell.dart';
import 'vintage_guidance_compass.dart';

/// Compact vintage map chip: timer + STOP for Terrain Echo (draggable).
class TerrainEchoHud extends StatelessWidget {
  const TerrainEchoHud({super.key});

  @override
  Widget build(BuildContext context) {
    final echo = context.watch<TerrainEchoController>();
    if (!echo.isActive) return const SizedBox.shrink();

    return ActiveToolHudShell(
      icon: const _EchoRadarIcon(size: 26),
      remainingListenable: echo.remainingListenable,
      onStop: () => echo.stop(),
      body: Text(
        'ECHO',
        style: VintageInstrumentStyle.mono.copyWith(
          fontSize: 9,
          letterSpacing: 1.2,
          color: VintageInstrumentStyle.brassMuted,
        ),
      ),
    );
  }
}

class _EchoRadarIcon extends StatelessWidget {
  const _EchoRadarIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _EchoRadarIconPainter()),
    );
  }
}

class _EchoRadarIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.38;
    final rim = Paint()
      ..color = VintageInstrumentStyle.brassRim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final face = Paint()..color = const Color(0xFF1A1208);
    canvas.drawCircle(center, r, face);
    canvas.drawCircle(center, r, rim);
    canvas.drawCircle(center, r * 0.55, rim..strokeWidth = 0.9);
    final sweep = Paint()
      ..color = const Color(0x99C4A35A)
      ..style = PaintingStyle.fill;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r * 0.92),
      -1.2,
      0.7,
      true,
      sweep,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
