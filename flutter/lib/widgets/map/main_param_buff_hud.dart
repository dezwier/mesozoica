import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/main_param_buff_controller.dart';
import '../../models/main_param_buff_kind.dart';
import 'active_tool_hud_shell.dart';
import 'vintage_guidance_compass.dart';

/// Compact vintage map chip: timer + STOP for any main-param buff tool.
class MainParamBuffHud extends StatelessWidget {
  const MainParamBuffHud({super.key});

  @override
  Widget build(BuildContext context) {
    final buff = context.watch<MainParamBuffController>();
    if (!buff.isActive) return const SizedBox.shrink();
    final kind = buff.kind ?? MainParamBuffKind.ridgeGlass;

    return ActiveToolHudShell(
      icon: _iconForKind(kind),
      remainingListenable: buff.remainingListenable,
      onStop: () => buff.stop(),
      body: Text(
        kind.hudLabel,
        style: VintageInstrumentStyle.mono.copyWith(
          fontSize: 9,
          letterSpacing: 1.2,
          color: VintageInstrumentStyle.brassMuted,
        ),
      ),
    );
  }

  Widget _iconForKind(MainParamBuffKind kind) {
    if (kind.actionKey == MainParamBuffKind.trailStriders.actionKey) {
      return const _TrailStridersIcon(size: 26);
    }
    if (kind.actionKey == MainParamBuffKind.expeditionDrivetrain.actionKey) {
      return const _DrivetrainIcon(size: 26);
    }
    if (kind.actionKey == MainParamBuffKind.canyonThrottle.actionKey) {
      return const _CanyonThrottleIcon(size: 26);
    }
    if (kind.actionKey == MainParamBuffKind.overlandChassis.actionKey) {
      return const _OverlandChassisIcon(size: 26);
    }
    if (kind.actionKey == MainParamBuffKind.nocturneLens.actionKey) {
      return const _NocturneIcon(size: 26);
    }
    return const _RidgeGlassIcon(size: 26);
  }
}

/// Back-compat aliases used by map_screen until fully migrated.
class RidgeGlassHud extends StatelessWidget {
  const RidgeGlassHud({super.key});

  @override
  Widget build(BuildContext context) => const MainParamBuffHud();
}

class ExpeditionDrivetrainHud extends StatelessWidget {
  const ExpeditionDrivetrainHud({super.key});

  @override
  Widget build(BuildContext context) => const MainParamBuffHud();
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

class _TrailStridersIcon extends StatelessWidget {
  const _TrailStridersIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _TrailStridersIconPainter()),
    );
  }
}

class _TrailStridersIconPainter extends CustomPainter {
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

    final sole = Paint()
      ..color = VintageInstrumentStyle.brassRim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(center.dx - r * 0.45, center.dy + r * 0.35)
      ..quadraticBezierTo(
        center.dx - r * 0.55,
        center.dy - r * 0.1,
        center.dx - r * 0.15,
        center.dy - r * 0.45,
      )
      ..quadraticBezierTo(
        center.dx + r * 0.35,
        center.dy - r * 0.35,
        center.dx + r * 0.4,
        center.dy + r * 0.15,
      )
      ..quadraticBezierTo(
        center.dx + r * 0.15,
        center.dy + r * 0.45,
        center.dx - r * 0.45,
        center.dy + r * 0.35,
      );
    canvas.drawPath(path, sole);
    canvas.drawLine(
      Offset(center.dx - r * 0.25, center.dy + r * 0.05),
      Offset(center.dx + r * 0.2, center.dy - r * 0.05),
      sole,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CanyonThrottleIcon extends StatelessWidget {
  const _CanyonThrottleIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CanyonThrottleIconPainter()),
    );
  }
}

class _CanyonThrottleIconPainter extends CustomPainter {
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

    final stroke = Paint()
      ..color = VintageInstrumentStyle.brassRim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    // Two small wheels + frame triangle.
    canvas.drawCircle(
      Offset(center.dx - r * 0.35, center.dy + r * 0.25),
      r * 0.28,
      stroke,
    );
    canvas.drawCircle(
      Offset(center.dx + r * 0.35, center.dy + r * 0.25),
      r * 0.28,
      stroke,
    );
    canvas.drawLine(
      Offset(center.dx - r * 0.35, center.dy + r * 0.25),
      Offset(center.dx, center.dy - r * 0.35),
      stroke,
    );
    canvas.drawLine(
      Offset(center.dx + r * 0.35, center.dy + r * 0.25),
      Offset(center.dx, center.dy - r * 0.35),
      stroke,
    );
    canvas.drawLine(
      Offset(center.dx - r * 0.35, center.dy + r * 0.25),
      Offset(center.dx + r * 0.35, center.dy + r * 0.25),
      stroke,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - r * 0.35),
      Offset(center.dx + r * 0.45, center.dy - r * 0.55),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _OverlandChassisIcon extends StatelessWidget {
  const _OverlandChassisIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _OverlandChassisIconPainter()),
    );
  }
}

class _OverlandChassisIconPainter extends CustomPainter {
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

    final stroke = Paint()
      ..color = VintageInstrumentStyle.brassRim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy - r * 0.05),
        width: r * 1.35,
        height: r * 0.7,
      ),
      const Radius.circular(2),
    );
    canvas.drawRRect(body, stroke);
    canvas.drawCircle(
      Offset(center.dx - r * 0.4, center.dy + r * 0.4),
      r * 0.22,
      stroke,
    );
    canvas.drawCircle(
      Offset(center.dx + r * 0.4, center.dy + r * 0.4),
      r * 0.22,
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NocturneIcon extends StatelessWidget {
  const _NocturneIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _NocturneIconPainter()),
    );
  }
}

class _NocturneIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.36;
    final rim = Paint()
      ..color = VintageInstrumentStyle.brassRim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final glass = Paint()..color = const Color(0x8830A050);
    canvas.drawCircle(center, r, glass);
    canvas.drawCircle(center, r, rim);
    final glow = Paint()
      ..color = const Color(0x6640FF70)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, r * 0.4, glow);
    final bridge = Paint()
      ..color = VintageInstrumentStyle.brassRim
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center.translate(-r * 1.05, -r * 0.15),
      center.translate(-r * 0.55, -r * 0.55),
      bridge,
    );
    canvas.drawLine(
      center.translate(r * 1.05, -r * 0.15),
      center.translate(r * 0.55, -r * 0.55),
      bridge,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
