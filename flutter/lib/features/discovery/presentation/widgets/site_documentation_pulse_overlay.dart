import 'package:flutter/material.dart';

/// Fast gold wash over a site marker image while documentation is active.
///
/// Full fade-in/out cycle completes in [period] (default 0.5s).
class SiteDocumentationPulseOverlay extends StatefulWidget {
  const SiteDocumentationPulseOverlay({
    super.key,
    required this.active,
    this.color = const Color.fromARGB(255, 255, 255, 255),
    this.period = const Duration(milliseconds: 1000),
    this.minOpacity = 0.08,
    this.maxOpacity = 0.42,
  });

  final bool active;
  final Color color;
  final Duration period;
  final double minOpacity;
  final double maxOpacity;

  @override
  State<SiteDocumentationPulseOverlay> createState() =>
      _SiteDocumentationPulseOverlayState();
}

class _SiteDocumentationPulseOverlayState
    extends State<SiteDocumentationPulseOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _halfPeriod);
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant SiteDocumentationPulseOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      _controller.duration = _halfPeriod;
    }
    if (oldWidget.active != widget.active) {
      _syncAnimation();
    }
  }

  Duration get _halfPeriod {
    final ms = widget.period.inMilliseconds;
    return Duration(milliseconds: (ms / 2).round().clamp(1, 1 << 30));
  }

  void _syncAnimation() {
    if (widget.active) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_controller.value);
          final opacity =
              widget.minOpacity + (widget.maxOpacity - widget.minOpacity) * t;
          return ColoredBox(color: widget.color.withValues(alpha: opacity));
        },
      ),
    );
  }
}
