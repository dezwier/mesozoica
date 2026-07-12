import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../theme/dino_card_theme.dart';
import 'dino_fact_row.dart';
import 'fossil_card_header.dart';
import 'fossil_card_image.dart';

class FossilCardBack extends StatelessWidget {
  const FossilCardBack({super.key, required this.fossil});

  final FossilSummary fossil;

  static const _icon = 'assets/images/cards/icons/location.svg';

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: DinoCardTheme.of(context).cardBackground),
          Opacity(
            opacity: 0.1,
            child: FossilCardImage(imageUrl: fossil.mainImageUrl),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FossilCardHeader(
                  fossil: fossil,
                  titleFontSize: 24,
                  centered: true,
                  useFrontTitleStyle: true,
                  wrapTitle: true,
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: _TwoColumnFields(fields: fossil.storedFields),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TwoColumnFields extends StatelessWidget {
  const _TwoColumnFields({required this.fields});

  final List<FossilStoredField> fields;

  static const _icon = FossilCardBack._icon;
  static const _columnGap = 12.0;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) {
      return const SizedBox.shrink();
    }

    final midpoint = (fields.length / 2).ceil();
    final leftFields = fields.sublist(0, midpoint);
    final rightFields = fields.sublist(midpoint);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _FieldColumn(fields: leftFields)),
        const SizedBox(width: _columnGap),
        Expanded(child: _FieldColumn(fields: rightFields)),
      ],
    );
  }
}

class _FieldColumn extends StatelessWidget {
  const _FieldColumn({required this.fields});

  final List<FossilStoredField> fields;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final field in fields)
          DinoFactRow(
            iconAsset: _TwoColumnFields._icon,
            label: field.label,
            value: field.value,
            compact: true,
            wrapValue: true,
          ),
      ],
    );
  }
}
