import 'package:flutter/material.dart';

import '../../config/game_config.dart';
import '../../models/disguise_tool_kind.dart';
import '../../theme/dino_card_theme.dart';
import '../tools/tool_stat_row.dart';

/// Stats panel for Brush Scrim / Blackout Cover.
class DisguiseToolStats extends StatelessWidget {
  const DisguiseToolStats({
    super.key,
    required this.kind,
    this.params,
    this.compact = false,
  });

  final DisguiseToolKind kind;
  final Map<String, dynamic>? params;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cfg = GameConfig.instance.toolActions.disguiseConfigFor(kind.actionKey);
    final p = params;
    final durationMinutes =
        (p?['duration_minutes'] as num?)?.toInt() ?? cfg.durationMinutes;
    final multiplier = (p?['discovery_chance_multiplier'] as num?)?.toDouble() ??
        cfg.discoveryChanceMultiplier;
    final xp = (p?['xp'] as num?)?.toInt() ?? cfg.xp;
    final explanation = p?['stats_explanation'] as String? ?? '';

    final pairs = <ToolStatPair>[
      ToolStatPair('Duration', '$durationMinutes min'),
      ToolStatPair(
        'Rival chance',
        '×${multiplier.toStringAsFixed(multiplier == 0 || multiplier == 1 ? 0 : 1)}',
      ),
      ToolStatPair('Stewardship XP', '$xp'),
    ];

    if (compact) {
      return Text(
        pairs.map((r) => '${r.label} ${r.value}').join(' · '),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final cardTheme = DinoCardTheme.of(context);
    final mutedStyle = cardTheme.bodyStyle(fontSize: 11).copyWith(
          color: cardTheme.cardTextMuted,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ToolStatGrid(
          pairs: pairs.map((p) => ToolStatPair(p.label, p.value)).toList(),
        ),
        if (explanation.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(explanation, style: mutedStyle),
        ],
      ],
    );
  }
}
