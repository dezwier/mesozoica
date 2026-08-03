import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/disguise_session_controller.dart';
import '../../models/disguise_tool_kind.dart';
import 'active_tool_hud_shell.dart';
import 'vintage_guidance_compass.dart';

/// Map chip while picking a site or while a disguise cover is live.
class DisguiseHud extends StatelessWidget {
  const DisguiseHud({super.key});

  @override
  Widget build(BuildContext context) {
    final disguise = context.watch<DisguiseSessionController>();
    if (disguise.isPickMode) {
      final verb = disguise.kind == DisguiseToolKind.blackoutCover
          ? 'SHROUD'
          : 'CONCEAL';
      return ActiveToolHudShell(
        icon: const _DisguiseIcon(size: 26),
        remainingListenable: disguise.remainingListenable,
        onStop: disguise.cancelPick,
        stopLabel: 'CANCEL',
        body: Text(
          'TAP A SITE · $verb',
          style: VintageInstrumentStyle.mono.copyWith(
            fontSize: 9,
            letterSpacing: 1.0,
            color: VintageInstrumentStyle.brassMuted,
          ),
        ),
      );
    }

    if (!disguise.isActive) return const SizedBox.shrink();

    final verb = disguise.kind == DisguiseToolKind.blackoutCover
        ? 'SHROUD'
        : 'CONCEAL';
    return ActiveToolHudShell(
      icon: const _DisguiseIcon(size: 26),
      remainingListenable: disguise.remainingListenable,
      onStop: () => disguise.stop(),
      body: Text(
        verb,
        style: VintageInstrumentStyle.mono.copyWith(
          fontSize: 9,
          letterSpacing: 1.2,
          color: VintageInstrumentStyle.brassMuted,
        ),
      ),
    );
  }
}

class _DisguiseIcon extends StatelessWidget {
  const _DisguiseIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DisguiseIconPainter()),
    );
  }
}

class _DisguiseIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.36;
    final rim = Paint()
      ..color = VintageInstrumentStyle.brassRim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final veil = Paint()..color = const Color(0x664A3A20);
    canvas.drawCircle(center, r, veil);
    canvas.drawCircle(center, r, rim);
    final fold = Paint()
      ..color = VintageInstrumentStyle.gold.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r * 0.55),
      0.4,
      2.2,
      false,
      fold,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
