import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/dino_card_theme.dart';

class CardFactEntry {
  const CardFactEntry({
    required this.iconAsset,
    required this.label,
    required this.value,
    this.maxValueLines = 2,
  });

  final String iconAsset;
  final String label;
  final String value;
  final int maxValueLines;
}

enum CardFactPanelLayout { wrap, columnGrid }

/// Full-width stat panel for card backs (profile-card elevation style).
class CardFactPanel extends StatelessWidget {
  const CardFactPanel({
    super.key,
    required this.facts,
    this.columns = 3,
    this.layout = CardFactPanelLayout.wrap,
    this.centerColumns = false,
  });

  final List<CardFactEntry> facts;
  final int columns;
  final CardFactPanelLayout layout;
  final bool centerColumns;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    return DecoratedBox(
      decoration: cardTheme.factPanelDecoration(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (layout == CardFactPanelLayout.columnGrid) {
              return _buildColumnGrid(context, constraints.maxWidth);
            }
            return _buildWrap(context, constraints.maxWidth);
          },
        ),
      ),
    );
  }

  Widget _buildColumnGrid(BuildContext context, double maxWidth) {
    final columnCount = columns.clamp(1, facts.length);
    final cellWidth = (maxWidth - ((columnCount - 1) * 8)) / columnCount;
    final columnFacts = List<List<CardFactEntry>>.generate(
      columnCount,
      (_) => <CardFactEntry>[],
    );

    for (var index = 0; index < facts.length; index++) {
      columnFacts[index % columnCount].add(facts[index]);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var column = 0; column < columnCount; column++) ...[
          if (column > 0) const SizedBox(width: 8),
          SizedBox(
            width: cellWidth,
            child: Column(
              crossAxisAlignment: centerColumns
                  ? CrossAxisAlignment.stretch
                  : CrossAxisAlignment.start,
              children: [
                for (var row = 0; row < columnFacts[column].length; row++) ...[
                  if (row > 0) const SizedBox(height: 8),
                  _CardFactCell(
                    iconAsset: columnFacts[column][row].iconAsset,
                    label: columnFacts[column][row].label,
                    value: columnFacts[column][row].value,
                    maxValueLines: columnFacts[column][row].maxValueLines,
                    centered: centerColumns,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWrap(BuildContext context, double maxWidth) {
    final columnCount = columns.clamp(1, facts.length);
    final cellWidth = (maxWidth - ((columnCount - 1) * 8)) / columnCount;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: [
        for (final fact in facts)
          SizedBox(
            width: cellWidth,
            child: _CardFactCell(
              iconAsset: fact.iconAsset,
              label: fact.label,
              value: fact.value,
              maxValueLines: fact.maxValueLines,
            ),
          ),
      ],
    );
  }
}

class _CardFactCell extends StatelessWidget {
  const _CardFactCell({
    required this.iconAsset,
    required this.label,
    required this.value,
    this.maxValueLines = 2,
    this.centered = false,
  });

  final String iconAsset;
  final String label;
  final String value;
  final int maxValueLines;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: centered ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: centered
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            SvgPicture.asset(
              iconAsset,
              width: 12,
              height: 12,
              colorFilter: ColorFilter.mode(
                cardTheme.cardAccent,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label.toUpperCase(),
                style: cardTheme.statLabelStyle(fontSize: 7.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: centered ? TextAlign.center : TextAlign.start,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: cardTheme
              .statValueStyle(fontSize: 11.5)
              .copyWith(fontWeight: FontWeight.w600, height: 1.15),
          maxLines: maxValueLines,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
          textAlign: centered ? TextAlign.center : TextAlign.start,
        ),
      ],
    );
  }
}
