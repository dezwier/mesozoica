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
  });

  final Widget icon;
  final ValueNotifier<Duration?> remainingListenable;
  final VoidCallback onStop;
  final List<SurveyLegendEntry> legend;

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
                            child: Wrap(
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

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.entry});

  final SurveyLegendEntry entry;

  @override
  Widget build(BuildContext context) {
    return Row(
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
          ),
        ),
      ],
    );
  }
}

Color surveyRgbColor((int, int, int) rgb) =>
    Color.fromARGB(255, rgb.$1, rgb.$2, rgb.$3);

String surveyLegendLabel(String raw, {int maxChars = 8}) {
  final cleaned = raw.trim().replaceAll('_', ' ');
  if (cleaned.isEmpty) return '?';
  final titled = cleaned
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
  if (titled.length <= maxChars) return titled;
  return '${titled.substring(0, maxChars - 1)}…';
}
