import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/display_text.dart';

/// Compact five-up odd_* scores under the site attribute box.
class SiteCardOddFacts extends StatelessWidget {
  const SiteCardOddFacts({
    super.key,
    required this.site,
  });

  final SiteSummary site;

  static String _formatOdd(double? value) {
    if (value == null) return displayFactValue(null);
    return value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final entries = <(String, String)>[
      ('Dinos', _formatOdd(site.oddDinoCount)),
      ('Fossils', _formatOdd(site.oddFossilCount)),
      ('Complete', _formatOdd(site.oddCompleteness)),
      ('Quality', _formatOdd(site.oddQuality)),
      ('Depth', _formatOdd(site.oddDepth)),
    ];

    return DecoratedBox(
      decoration: cardTheme.factPanelDecoration(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entries[i].$1.toUpperCase(),
                      style: cardTheme.statLabelStyle(fontSize: 6.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entries[i].$2,
                      style: cardTheme.statValueStyle(fontSize: 10).copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
