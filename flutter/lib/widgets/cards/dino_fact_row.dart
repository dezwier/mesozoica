import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/dino_card_theme.dart';

class DinoFactRow extends StatelessWidget {
  const DinoFactRow({
    super.key,
    required this.iconAsset,
    required this.label,
    required this.value,
  });

  final String iconAsset;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SvgPicture.asset(
            iconAsset,
            width: 18,
            height: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: DinoCardTheme.statLabelStyle(fontSize: 10),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: DinoCardTheme.statValueStyle(fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
