import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/ridge_glass_controller.dart';
import 'active_tool_hud_shell.dart';
import 'vintage_guidance_compass.dart';

/// Compact vintage map chip: timer + STOP for Ridge Glass (draggable).
class RidgeGlassHud extends StatelessWidget {
  const RidgeGlassHud({super.key});

  @override
  Widget build(BuildContext context) {
    final ridge = context.watch<RidgeGlassController>();
    if (!ridge.isActive) return const SizedBox.shrink();

    return ActiveToolHudShell(
      icon: const _RidgeGlassIcon(size: 26),
      remainingListenable: ridge.remainingListenable,
      onStop: () => ridge.stop(),
      body: Text(
        'SCOUT',
        style: VintageInstrumentStyle.mono.copyWith(
          fontSize: 9,
          letterSpacing: 1.2,
          color: VintageInstrumentStyle.brassMuted,
        ),
      ),
    );
  }
}

class _RidgeGlassIcon extends StatelessWidget {
  const _RidgeGlassIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _RidgeGlassIconPainter()),
    );
  }
}

class _RidgeGlassIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.36;
    final rim = Paint()
      ..color = VintageInstrumentStyle.brassRim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final glass = Paint()..color = const Color(0x662A3A48);
    canvas.drawCircle(center, r, glass);
    canvas.drawCircle(center, r, rim);
    final lens = Paint()
      ..color = const Color(0x44C4D4E0)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center.translate(-r * 0.15, -r * 0.15), r * 0.35, lens);
    final bridge = Paint()
      ..color = VintageInstrumentStyle.brassRim
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center.translate(-r * 0.95, 0),
      center.translate(r * 0.95, 0),
      bridge,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
