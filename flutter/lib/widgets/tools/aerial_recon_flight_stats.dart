import 'package:flutter/material.dart';

import '../../config/game_config.dart';
import '../../services/tool_service.dart';
import '../../theme/dino_card_theme.dart';

/// Shared display of aerial recon flight / deploy knobs.
class AerialReconFlightStats extends StatelessWidget {
  const AerialReconFlightStats({
    super.key,
    required this.flightSpeedKmh,
    required this.maxRouteKm,
    required this.discoveryChance,
    required this.discoveryDistanceM,
    this.routeLengthKm,
    this.discoveredSiteCount,
    this.explanation,
    this.compact = false,
  });

  /// From current [GameConfig] (deploy-now stats).
  factory AerialReconFlightStats.fromConfig({
    Key? key,
    bool compact = false,
    bool includeExplanation = true,
  }) {
    final cfg = GameConfig.instance.toolActions.aerialRecon;
    return AerialReconFlightStats(
      key: key,
      flightSpeedKmh: cfg.flightSpeedKmh,
      maxRouteKm: cfg.maxRouteKm,
      discoveryChance: cfg.discoveryChance,
      discoveryDistanceM: cfg.discoveryDistanceM,
      explanation: includeExplanation ? cfg.statsExplanation : null,
      compact: compact,
    );
  }

  /// From a mission snapshot (with config fallback for legacy nulls).
  factory AerialReconFlightStats.fromMission(
    AerialReconMission mission, {
    Key? key,
    bool compact = false,
    bool includeRouteAndSites = true,
  }) {
    final cfg = GameConfig.instance.toolActions.aerialRecon;
    return AerialReconFlightStats(
      key: key,
      flightSpeedKmh: mission.flightSpeedKmh ?? cfg.flightSpeedKmh,
      maxRouteKm: mission.maxRouteKm ?? cfg.maxRouteKm,
      discoveryChance: mission.discoveryChance ?? cfg.discoveryChance,
      discoveryDistanceM:
          mission.discoveryDistanceM ?? cfg.discoveryDistanceM,
      routeLengthKm: includeRouteAndSites ? mission.routeLengthKm : null,
      discoveredSiteCount:
          includeRouteAndSites ? mission.discoveredSiteCount : null,
      compact: compact,
    );
  }

  final double flightSpeedKmh;
  final double maxRouteKm;
  final double discoveryChance;
  final double discoveryDistanceM;
  final double? routeLengthKm;
  final int? discoveredSiteCount;
  final String? explanation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final rows = <_StatPair>[
      _StatPair('Speed', _formatKmh(flightSpeedKmh)),
      _StatPair('Max range', _formatKm(maxRouteKm)),
      _StatPair('Discover', _formatChance(discoveryChance)),
      _StatPair('Distance', _formatMeters(discoveryDistanceM)),
      if (routeLengthKm != null)
        _StatPair('Route', _formatKm(routeLengthKm!)),
      if (discoveredSiteCount != null)
        _StatPair(
          'Sites',
          discoveredSiteCount == 1
              ? '1 found'
              : '$discoveredSiteCount found',
        ),
    ];

    if (compact) {
      return Text(
        rows.map((r) => '${r.label} ${r.value}').join(' · '),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final cardTheme = DinoCardTheme.of(context);
    final headerStyle = cardTheme.sectionLabelStyle(fontSize: 8);
    final bodyStyle = cardTheme.bodyStyle(fontSize: 12);
    final mutedStyle = cardTheme.bodyStyle(fontSize: 11).copyWith(
          color: cardTheme.cardTextMuted,
          height: 1.25,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (explanation != null && explanation!.isNotEmpty) ...[
          Text(explanation!, style: mutedStyle),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(flex: 5, child: Text('PARAM', style: headerStyle)),
            Expanded(flex: 4, child: Text('VALUE', style: headerStyle)),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Text(rows[i].label, style: bodyStyle),
              ),
              Expanded(
                flex: 4,
                child: Text(rows[i].value, style: bodyStyle),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static String _formatKmh(double v) {
    final label = v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(1);
    return '$label km/h';
  }

  static String _formatKm(double v) {
    final label = v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(1);
    return '$label km';
  }

  static String _formatChance(double v) {
    final pct = v * 100;
    final label = pct == pct.roundToDouble()
        ? pct.toStringAsFixed(0)
        : pct.toStringAsFixed(1);
    return '$label%';
  }

  static String _formatMeters(double v) {
    final label = v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(0);
    return '${label}m';
  }
}

class _StatPair {
  const _StatPair(this.label, this.value);

  final String label;
  final String value;
}
