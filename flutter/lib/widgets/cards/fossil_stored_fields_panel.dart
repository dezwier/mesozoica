import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import 'dino_fact_row.dart';

/// Two-column scrollable panel of fossil stored fields for card backs.
class FossilStoredFieldsPanel extends StatelessWidget {
  const FossilStoredFieldsPanel({super.key, required this.fields});

  final List<FossilStoredField> fields;

  static const _icon = 'assets/images/cards/icons/location.svg';
  static const _columnGap = 12.0;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) {
      return const SizedBox.shrink();
    }

    final midpoint = (fields.length / 2).ceil();
    final leftFields = fields.sublist(0, midpoint);
    final rightFields = fields.sublist(midpoint);

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _FieldColumn(fields: leftFields)),
          const SizedBox(width: _columnGap),
          Expanded(child: _FieldColumn(fields: rightFields)),
        ],
      ),
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
            iconAsset: FossilStoredFieldsPanel._icon,
            label: field.label,
            value: field.value,
            compact: true,
            wrapValue: true,
          ),
      ],
    );
  }
}
