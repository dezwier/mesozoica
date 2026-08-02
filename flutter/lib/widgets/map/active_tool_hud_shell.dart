import 'package:flutter/material.dart';

import '../../shell/map_chrome_insets.dart';
import 'vintage_guidance_compass.dart';

/// Draggable brass map chip chrome shared by timed-tool and aerial HUDs.
class VintageMapHudChip extends StatefulWidget {
  const VintageMapHudChip({
    super.key,
    required this.child,
    this.maxWidth = 280,
    this.onTap,
  });

  final Widget child;
  final double maxWidth;
  /// Fired on a tap that is not a drag (e.g. follow / re-center).
  final VoidCallback? onTap;

  @override
  State<VintageMapHudChip> createState() => _VintageMapHudChipState();
}

class _VintageMapHudChipState extends State<VintageMapHudChip> {
  Offset _dragOffset = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final top = MapChromeInsets.top(context) + 8;
    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: Align(
          alignment: Alignment.topCenter,
          child: Transform.translate(
            offset: _dragOffset,
            child: GestureDetector(
              onTap: widget.onTap,
              onPanUpdate: (details) {
                setState(() => _dragOffset += details.delta);
              },
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
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: widget.maxWidth),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared draggable map chip for timed tool sessions (duration + STOP).
///
/// Defaults to center-top under archive/field chrome; drag anywhere on screen.
/// Optional [body] holds tool-specific extras (legends, etc.).
class ActiveToolHudShell extends StatelessWidget {
  const ActiveToolHudShell({
    super.key,
    required this.icon,
    required this.remainingListenable,
    required this.onStop,
    this.stopLabel = 'STOP',
    this.onTap,
    this.body,
    this.maxWidth = 280,
  });

  final Widget icon;
  final ValueNotifier<Duration?> remainingListenable;
  final VoidCallback onStop;
  final String stopLabel;
  /// Chip tap (not drag / not STOP) — e.g. follow an aerial scout.
  final VoidCallback? onTap;
  final Widget? body;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final body = this.body;
    return VintageMapHudChip(
      maxWidth: maxWidth,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: 8),
              ValueListenableBuilder<Duration?>(
                valueListenable: remainingListenable,
                builder: (context, remaining, _) {
                  return Text(
                    formatActiveToolHudRemaining(remaining),
                    style: VintageInstrumentStyle.mono.copyWith(
                      fontSize: 13,
                      color: VintageInstrumentStyle.live,
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onStop,
                behavior: HitTestBehavior.opaque,
                // Absorb so chip [onTap] (e.g. follow) does not also fire.
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                  child: Text(
                    stopLabel,
                    style: VintageInstrumentStyle.mono.copyWith(
                      fontSize: 12,
                      color: VintageInstrumentStyle.stop,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (body != null) ...[
            const SizedBox(height: 6),
            body,
          ],
        ],
      ),
    );
  }
}

class SurveyLegendEntry {
  const SurveyLegendEntry({required this.label, required this.color});

  final String label;
  final Color color;
}

/// Orbit / Formation convenience wrapper: duration/STOP + color legend body.
class SurveyMapHudShell extends StatelessWidget {
  const SurveyMapHudShell({
    super.key,
    required this.icon,
    required this.remainingListenable,
    required this.onStop,
    required this.legend,
    this.collapseLegendToTwoLines = false,
  });

  final Widget icon;
  final ValueNotifier<Duration?> remainingListenable;
  final VoidCallback onStop;
  final List<SurveyLegendEntry> legend;
  final bool collapseLegendToTwoLines;

  @override
  Widget build(BuildContext context) {
    return ActiveToolHudShell(
      icon: icon,
      remainingListenable: remainingListenable,
      onStop: onStop,
      body: legend.isEmpty
          ? null
          : collapseLegendToTwoLines
              ? _CollapsibleLegend(entries: legend)
              : Wrap(
                  spacing: 6,
                  runSpacing: 3,
                  children: [
                    for (final entry in legend) _LegendChip(entry: entry),
                  ],
                ),
    );
  }
}

class _CollapsibleLegend extends StatefulWidget {
  const _CollapsibleLegend({required this.entries});

  final List<SurveyLegendEntry> entries;

  @override
  State<_CollapsibleLegend> createState() => _CollapsibleLegendState();
}

class _CollapsibleLegendState extends State<_CollapsibleLegend> {
  static const _chipLineHeight = 12.0;
  static const _runSpacing = 3.0;
  static const _collapsedHeight = _chipLineHeight * 2 + _runSpacing;

  bool _expanded = false;
  bool _overflows = false;
  final GlobalKey _measureKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureOverflow());
  }

  @override
  void didUpdateWidget(covariant _CollapsibleLegend oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries.length != widget.entries.length ||
        !_sameLabels(oldWidget.entries, widget.entries)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureOverflow());
    }
  }

  bool _sameLabels(
    List<SurveyLegendEntry> a,
    List<SurveyLegendEntry> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].label != b[i].label) return false;
    }
    return true;
  }

  void _measureOverflow() {
    final box = _measureKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final overflows = box.size.height > _collapsedHeight + 0.5;
    if (overflows != _overflows && mounted) {
      setState(() => _overflows = overflows);
    }
  }

  Widget _buildWrap() {
    return Wrap(
      spacing: 6,
      runSpacing: _runSpacing,
      children: [
        for (final entry in widget.entries) _LegendChip(entry: entry),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Offstage(
          offstage: true,
          child: KeyedSubtree(key: _measureKey, child: _buildWrap()),
        ),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: double.infinity,
              height: (_expanded || !_overflows) ? null : _collapsedHeight,
              child: _buildWrap(),
            ),
          ),
        ),
        if (_overflows) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Text(
              _expanded ? 'LESS' : 'MORE',
              style: VintageInstrumentStyle.mono.copyWith(
                fontSize: 9,
                letterSpacing: 0.8,
                color: VintageInstrumentStyle.brassRim,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.entry});

  final SurveyLegendEntry entry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _CollapsibleLegendState._chipLineHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: entry.color,
              borderRadius: BorderRadius.circular(1.5),
              border: Border.all(
                color: VintageInstrumentStyle.brassRim.withValues(alpha: 0.7),
                width: 0.6,
              ),
            ),
          ),
          const SizedBox(width: 3),
          Text(
            entry.label,
            style: VintageInstrumentStyle.mono.copyWith(
              fontSize: 9,
              letterSpacing: 0.6,
              color: VintageInstrumentStyle.brassMuted,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

Color surveyRgbColor((int, int, int) rgb) =>
    Color.fromARGB(255, rgb.$1, rgb.$2, rgb.$3);

/// Title-case rock/period labels; never truncates.
String surveyLegendLabel(String raw) {
  final cleaned = raw.trim().replaceAll('_', ' ');
  if (cleaned.isEmpty) return '?';
  return cleaned
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
