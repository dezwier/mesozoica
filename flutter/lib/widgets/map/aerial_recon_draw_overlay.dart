import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/aerial_recon_controller.dart';
import '../../services/location_service.dart';
import 'mapbox_camera_coordinator.dart';

/// Full-screen draw layer for Aerial Recon scout loops.
class AerialReconDrawOverlay extends StatefulWidget {
  const AerialReconDrawOverlay({
    super.key,
    required this.camera,
  });

  final MapboxCameraCoordinator camera;

  @override
  State<AerialReconDrawOverlay> createState() => _AerialReconDrawOverlayState();
}

class _AerialReconDrawOverlayState extends State<AerialReconDrawOverlay> {
  final List<Offset> _screenPoints = [];
  AerialReconController? _recon;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final recon = context.read<AerialReconController>();
    if (!identical(recon, _recon)) {
      _recon?.removeListener(_onReconChanged);
      _recon = recon;
      _recon!.addListener(_onReconChanged);
    }
  }

  @override
  void dispose() {
    _recon?.removeListener(_onReconChanged);
    super.dispose();
  }

  void _onReconChanged() {
    final recon = _recon;
    if (recon == null) return;
    if (!recon.isDrawMode || recon.route.isEmpty) {
      if (_screenPoints.isNotEmpty) {
        setState(() => _screenPoints.clear());
      }
    }
  }

  Future<void> _handlePoint(Offset local, {required bool start}) async {
    final recon = context.read<AerialReconController>();
    final point = await widget.camera.coordinateForPixel(local);
    if (!mounted || point == null) return;
    if (start) {
      recon.startStroke(point);
      setState(() {
        _screenPoints
          ..clear()
          ..add(local);
      });
    } else {
      final before = recon.route.length;
      recon.appendPoint(point);
      if (recon.route.length > before) {
        setState(() => _screenPoints.add(local));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AerialReconController, LocationService>(
      builder: (context, recon, location, _) {
        if (!recon.isDrawMode) return const SizedBox.shrink();

        final top = MediaQuery.paddingOf(context).top + 12;
        final bottom = MediaQuery.paddingOf(context).bottom + 16;

        return Positioned.fill(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) {
                    _handlePoint(details.localPosition, start: true);
                  },
                  onPanUpdate: (details) {
                    _handlePoint(details.localPosition, start: false);
                  },
                  onPanEnd: (_) => recon.endStroke(),
                  onPanCancel: () => recon.endStroke(),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ScreenRoutePainter(points: _screenPoints),
                  ),
                ),
              ),
              Positioned(
                top: top,
                left: 16,
                right: 16,
                child: Material(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Text(
                      recon.message ??
                          'Draw a loop that starts and ends at your location. '
                          'Use the zoom slider as needed.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: bottom,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: recon.isSubmitting
                            ? null
                            : () => recon.cancelDraw(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: recon.isSubmitting || !recon.hasRoute
                            ? null
                            : () async {
                                final origin = location.currentLocation;
                                if (origin == null) {
                                  recon.clearRoute(
                                    message:
                                        'Waiting for your current location',
                                  );
                                  return;
                                }
                                final ok =
                                    await recon.submit(origin: origin);
                                if (!context.mounted) return;
                                if (ok) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Aerial Recon deployed — scouting in background',
                                      ),
                                    ),
                                  );
                                }
                              },
                        child: recon.isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Finish'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ScreenRoutePainter extends CustomPainter {
  _ScreenRoutePainter({required this.points});

  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = const Color(0xFFD4AF37)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);

    final dot = Paint()..color = const Color(0xFFD4AF37);
    canvas.drawCircle(points.first, 5, dot);
    canvas.drawCircle(points.last, 5, dot);
  }

  @override
  bool shouldRepaint(covariant _ScreenRoutePainter oldDelegate) =>
      oldDelegate.points != points;
}
