import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../controllers/guidance_session_controller.dart';
import '../../services/location_service.dart';
import '../../shell/map_chrome_insets.dart';
import 'proximity_scanner_display.dart';
import 'vintage_guidance_compass.dart';

/// Matches Mapbox FollowPuck enter / north-fixed exit camera duration.
const Duration _kOrientationTransition = Duration(milliseconds: 1200);

/// Guidance chrome (vintage compass / proximity readout) for rotate or
/// north-fixed follow. The compass is hidden while north-fixed and uncentered.
class GuidanceOverlay extends StatefulWidget {
  const GuidanceOverlay({
    super.key,
    required this.rotateWithHeading,
    required this.followUser,
  });

  /// True in AR rotate mode; false when the map is north-fixed.
  final bool rotateWithHeading;

  /// True while the camera is locked on the user (or rotate forces follow).
  final bool followUser;

  @override
  State<GuidanceOverlay> createState() => _GuidanceOverlayState();
}

class _GuidanceOverlayState extends State<GuidanceOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _modeAnim;
  late final Animation<double> _rotateT;

  @override
  void initState() {
    super.initState();
    _modeAnim = AnimationController(
      vsync: this,
      duration: _kOrientationTransition,
      value: widget.rotateWithHeading ? 1.0 : 0.0,
    );
    _rotateT = CurvedAnimation(parent: _modeAnim, curve: Curves.easeInOutCubic);
  }

  @override
  void didUpdateWidget(covariant GuidanceOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rotateWithHeading == widget.rotateWithHeading) return;
    if (widget.rotateWithHeading) {
      _modeAnim.forward();
    } else {
      _modeAnim.reverse();
    }
  }

  @override
  void dispose() {
    _modeAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guidance = context.watch<GuidanceSessionController>();
    if (!guidance.isActive) return const SizedBox.shrink();

    final location = context.read<LocationService>();
    final topInset = MapChromeInsets.top(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        guidance.displayTickListenable,
        guidance.remainingListenable,
        location.headingListenable,
      ]),
      builder: (context, _) {
        final remaining = guidance.remainingListenable.value;
        final showDistance =
            guidance.showDistance && guidance.distanceLabel != null;
        // Keep compass visible during exit animation even if follow flickers.
        final showCompass =
            guidance.showNeedle &&
            guidance.targetSite != null &&
            (widget.rotateWithHeading ||
                widget.followUser ||
                _modeAnim.isAnimating);
        // Session controls: proximity meter when distance UI is up (site nav /
        // proximity scanner); otherwise under the compass (geo compass).
        final sessionOnProximity = showDistance;

        return LayoutBuilder(
          builder: (context, constraints) {
            final compassSession = !sessionOnProximity;
            final compassH =
                VintageGuidanceCompass.size +
                (compassSession
                    ? VintageGuidanceCompass.sessionStripHeight
                    : 0);
            final heading = location.headingDeg;
            const compassTitle = 'COMPASS';
            final centerNorth = guidance.rangeCenterScreenDeg(
              rotateWithHeading: false,
            );
            final centerRotate = guidance.rangeCenterScreenDeg(
              rotateWithHeading: true,
            );

            return Stack(
              children: [
                if (showCompass)
                  AnimatedBuilder(
                    animation: _rotateT,
                    builder: (context, _) {
                      final t = _rotateT.value;
                      final focusFromBottom = lerpDouble(
                        0.5,
                        MapConfig.mapboxRotateFocusFromBottom,
                        t,
                      )!;
                      final focus = Offset(
                        constraints.maxWidth / 2,
                        constraints.maxHeight * (1 - focusFromBottom),
                      );
                      final centerDeg = _lerpDeg(centerNorth, centerRotate, t);
                      final northDeg = lerpDouble(0.0, -heading, t)!;

                      return Positioned(
                        left: focus.dx - VintageGuidanceCompass.size / 2,
                        top: focus.dy - VintageGuidanceCompass.size / 2,
                        width: VintageGuidanceCompass.size,
                        height: compassH,
                        child: VintageGuidanceCompass(
                          centerDeg: centerDeg,
                          rangeWidthDeg: guidance.rangeWidthDeg,
                          northDeg: northDeg,
                          remaining: compassSession ? remaining : null,
                          onStop: compassSession ? () => guidance.stop() : null,
                          title: compassTitle,
                        ),
                      );
                    },
                  ),
                if (showDistance)
                  DraggableProximityScanner(
                    key: ValueKey(guidance.session?.sessionId ?? 0),
                    label: guidance.distanceLabel!,
                    remaining: remaining,
                    onStop: () => guidance.stop(),
                  ),
                if (guidance.showRetargetBadge)
                  Positioned(
                    top:
                        topInset +
                        8 +
                        (showDistance
                            ? ProximityScannerDisplay.mapHeightEstimate + 8
                            : 0),
                    left: 16,
                    right: 16,
                    child: const Center(child: _RetargetBadge()),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Shortest-path interpolation for compass degrees.
double _lerpDeg(double a, double b, double t) {
  var delta = (b - a) % 360.0;
  if (delta > 180) delta -= 360;
  if (delta < -180) delta += 360;
  return a + delta * t;
}

class _RetargetBadge extends StatelessWidget {
  const _RetargetBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          'Closer site sensed',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
