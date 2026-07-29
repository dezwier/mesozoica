import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/formation_map_controller.dart';
import '../../shell/map_chrome_insets.dart';
import 'vintage_guidance_compass.dart';

/// Compact vintage map chip under Archive/Field: timer + stop.
class FormationMapHud extends StatelessWidget {
  const FormationMapHud({super.key});

  static const double iconSize = 44;

  @override
  Widget build(BuildContext context) {
    final formation = context.watch<FormationMapController>();
    if (!formation.isActive) return const SizedBox.shrink();

    final top = MapChromeInsets.top(context) + 8;

    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: VintageInstrumentStyle.dialFace.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: VintageInstrumentStyle.brassRim,
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _VintageMapIcon(size: 28),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<Duration?>(
                    valueListenable: formation.remainingListenable,
                    builder: (context, remaining, _) {
                      final minutesLeft = remaining?.inMinutes.clamp(0, 999);
                      final time =
                          minutesLeft == null ? '—' : '${minutesLeft}m';
                      return Text(
                        time,
                        style: VintageInstrumentStyle.mono.copyWith(
                          fontSize: 13,
                          color: VintageInstrumentStyle.live,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => formation.stop(),
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      'STOP',
                      style: VintageInstrumentStyle.mono.copyWith(
                        fontSize: 12,
                        color: VintageInstrumentStyle.stop,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
