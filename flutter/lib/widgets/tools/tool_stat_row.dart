import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

class ToolStatPair {
  const ToolStatPair(this.label, this.value);

  final String label;
  final String value;
}

/// Renders stat pairs in rows of 4.
class ToolStatGrid extends StatelessWidget {
  const ToolStatGrid({super.key, required this.pairs});

  final List<ToolStatPair> pairs;

  @override
  Widget build(BuildContext context) {
    final rows = <List<ToolStatPair>>[];
    for (var i = 0; i < pairs.length; i += 4) {
      rows.add(pairs.sublist(i, (i + 4).clamp(0, pairs.length)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _ToolStatRowWidget(pairs: rows[i]),
        ],
      ],
    );
  }
}

class _ToolStatRowWidget extends StatelessWidget {
  const _ToolStatRowWidget({required this.pairs});

  final List<ToolStatPair> pairs;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final labelStyle = cardTheme.sectionLabelStyle(fontSize: 7);
    final valueStyle = cardTheme.bodyStyle(fontSize: 11).copyWith(
          fontWeight: FontWeight.w600,
          height: 1.15,
        );
    // Pad to 4 to keep equal widths.
    final padded = [...pairs];
    while (padded.length < 4) {
      padded.add(const ToolStatPair('', ''));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < padded.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (padded[i].label.isNotEmpty)
                  Text(
                    padded[i].label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: labelStyle,
                  ),
                if (padded[i].value.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    padded[i].value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: valueStyle,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
