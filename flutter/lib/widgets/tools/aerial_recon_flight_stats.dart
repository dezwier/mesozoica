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
    this.compact = false,
  });

  /// From current [GameConfig] (deploy-now stats).
  factory AerialReconFlightStats.fromConfig({
    Key? key,
    bool compact = false,
  }) {
    final cfg = GameConfig.instance.toolActions.aerialRecon;
    return AerialReconFlightStats(
      key: key,
      flightSpeedKmh: cfg.flightSpeedKmh,
      maxRouteKm: cfg.maxRouteKm,
      discoveryChance: cfg.discoveryChance,
      discoveryDistanceM: cfg.discoveryDistanceM,
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
    final labelStyle = cardTheme.sectionLabelStyle(fontSize: 8);
    final valueStyle = cardTheme.bodyStyle(fontSize: 12);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = rows.length <= 4 ? 2 : 3;
        final cellWidth =
            (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final row in rows)
              SizedBox(
                width: cellWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.label.toUpperCase(), style: labelStyle),
                    const SizedBox(height: 2),
                    Text(row.value, style: valueStyle),
                  ],
                ),
              ),
          ],
        );
      },
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
