import 'package:flutter/material.dart';

import '../../shell/map_chrome_insets.dart';
import 'vintage_guidance_compass.dart';

class SurveyLegendEntry {
  const SurveyLegendEntry({required this.label, required this.color});

  final String label;
  final Color color;
}

/// Shared draggable map chip for Orbit Survey / Formation Map HUDs.
///
/// Defaults to center-top under archive/field chrome; drag anywhere on screen.
class SurveyMapHudShell extends StatefulWidget {
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

  /// When true, legend shows 2 lines with a MORE/LESS toggle if it overflows.
  final bool collapseLegendToTwoLines;

  @override
  State<SurveyMapHudShell> createState() => _SurveyMapHudShellState();
}

class _SurveyMapHudShellState extends State<SurveyMapHudShell> {
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
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            widget.icon,
                            const SizedBox(width: 8),
                            ValueListenableBuilder<Duration?>(
                              valueListenable: widget.remainingListenable,
                              builder: (context, remaining, _) {
                                final minutesLeft =
                                    remaining?.inMinutes.clamp(0, 999);
                                final time = minutesLeft == null
                                    ? '—'
                                    : '${minutesLeft}m';
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
                              onTap: widget.onStop,
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
                        if (widget.legend.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 280),
                            child: widget.collapseLegendToTwoLines
                                ? _CollapsibleLegend(entries: widget.legend)
                                : Wrap(
                                    spacing: 6,
                                    runSpacing: 3,
                                    children: [
                                      for (final entry in widget.legend)
                                        _LegendChip(entry: entry),
                                    ],
                                  ),
                          ),
                        ],
                      ],
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
        // Offstage full wrap to measure natural height.
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
