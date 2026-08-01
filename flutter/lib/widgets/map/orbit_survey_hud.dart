import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/game_config.dart';
import '../../controllers/orbit_survey_controller.dart';
import 'survey_map_hud_shell.dart';
import 'vintage_guidance_compass.dart';

/// Compact vintage map chip: timer, stop, period legend (draggable).
class OrbitSurveyHud extends StatelessWidget {
  const OrbitSurveyHud({super.key});

  @override
  Widget build(BuildContext context) {
    final survey = context.watch<OrbitSurveyController>();
    if (!survey.isActive) return const SizedBox.shrink();

    final colors = GameConfig.instance.periodColors.orbitSurvey;
    final legend = [
      SurveyLegendEntry(
        label: 'Cret',
        color: surveyRgbColor(colors.cretaceous),
      ),
      SurveyLegendEntry(
        label: 'Jur',
        color: surveyRgbColor(colors.jurassic),
      ),
      SurveyLegendEntry(
        label: 'Tri',
        color: surveyRgbColor(colors.triassic),
      ),
    ];

    return SurveyMapHudShell(
      icon: const _VintageMapIcon(size: 28),
      remainingListenable: survey.remainingListenable,
      onStop: () => survey.stop(),
      legend: legend,
    );
  }
}

class _VintageMapIcon extends StatelessWidget {
  const _VintageMapIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _VintageMapIconPainter(),
      ),
    );
  }
}

class _VintageMapIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(size.width * 0.08);
    final frame = Paint()
      ..color = VintageInstrumentStyle.brassRim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final fill = Paint()..color = VintageInstrumentStyle.brassMid;
    canvas.drawRRect(
      RRect.fromRectAndRadius(inset, const Radius.circular(3)),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(inset, const Radius.circular(3)),
      frame,
    );

    final fold = Paint()
      ..color = VintageInstrumentStyle.brassLight.withValues(alpha: 0.55)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(inset.left + inset.width * 0.22, inset.top + inset.height * 0.28)
      ..lineTo(
        inset.left + inset.width * 0.48,
        inset.top + inset.height * 0.55,
      )
      ..lineTo(
        inset.left + inset.width * 0.78,
        inset.top + inset.height * 0.32,
      )
      ..lineTo(
        inset.left + inset.width * 0.62,
        inset.top + inset.height * 0.78,
      )
      ..lineTo(
        inset.left + inset.width * 0.28,
        inset.top + inset.height * 0.72,
      )
      ..close();
    canvas.drawPath(path, fold);

    final grid = Paint()
      ..color = VintageInstrumentStyle.brassText.withValues(alpha: 0.35)
      ..strokeWidth = 0.8;
    canvas.drawLine(
      Offset(inset.left + inset.width * 0.5, inset.top + 3),
      Offset(inset.left + inset.width * 0.5, inset.bottom - 3),
      grid,
    );
    canvas.drawLine(
      Offset(inset.left + 3, inset.top + inset.height * 0.5),
      Offset(inset.right - 3, inset.top + inset.height * 0.5),
      grid,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
