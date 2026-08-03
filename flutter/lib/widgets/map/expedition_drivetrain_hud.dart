import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/expedition_drivetrain_controller.dart';
import 'active_tool_hud_shell.dart';
import 'vintage_guidance_compass.dart';

/// Compact vintage map chip: timer + STOP for Expedition Drivetrain.
class ExpeditionDrivetrainHud extends StatelessWidget {
  const ExpeditionDrivetrainHud({super.key});

  @override
  Widget build(BuildContext context) {
    final drive = context.watch<ExpeditionDrivetrainController>();
    if (!drive.isActive) return const SizedBox.shrink();

    return ActiveToolHudShell(
      icon: const _DrivetrainIcon(size: 26),
      remainingListenable: drive.remainingListenable,
      onStop: () => drive.stop(),
      body: Text(
        'RIDE',
        style: VintageInstrumentStyle.mono.copyWith(
          fontSize: 9,
          letterSpacing: 1.2,
          color: VintageInstrumentStyle.brassMuted,
        ),
      ),
    );
  }
}

class _DrivetrainIcon extends StatelessWidget {
  const _DrivetrainIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DrivetrainIconPainter()),
    );
  }
}

class _DrivetrainIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.34;
    final rim = Paint()
      ..color = VintageInstrumentStyle.brassRim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final fill = Paint()..color = const Color(0x662A3A48);
    canvas.drawCircle(center, r, fill);
    canvas.drawCircle(center, r, rim);
    canvas.drawCircle(center, r * 0.28, rim);

    final spoke = Paint()
      ..color = VintageInstrumentStyle.brassRim
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3;
      canvas.drawLine(
        center,
        center.translate(
          r * 0.85 * math.cos(angle),
          r * 0.85 * math.sin(angle),
        ),
        spoke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
