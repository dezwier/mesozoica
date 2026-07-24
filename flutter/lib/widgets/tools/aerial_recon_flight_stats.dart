import 'package:flutter/material.dart';

import '../../config/game_config.dart';
import '../../services/tool_service.dart';
import '../../theme/dino_card_theme.dart';

/// Shared display of aerial recon flight / deploy knobs (4 params per row).
class AerialReconFlightStats extends StatelessWidget {
  const AerialReconFlightStats({
    super.key,
    required this.flightSpeedKmh,
    required this.maxRouteKm,
    required this.discoveryChance,
    required this.discoveryDistanceM,
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
  }) {
    final cfg = GameConfig.instance.toolActions.aerialRecon;
    return AerialReconFlightStats(
      key: key,
      flightSpeedKmh: mission.flightSpeedKmh ?? cfg.flightSpeedKmh,
      maxRouteKm: mission.maxRouteKm ?? cfg.maxRouteKm,
      discoveryChance: mission.discoveryChance ?? cfg.discoveryChance,
      discoveryDistanceM:
          mission.discoveryDistanceM ?? cfg.discoveryDistanceM,
      compact: compact,
    );
  }

  final double flightSpeedKmh;
  final double maxRouteKm;
  final double discoveryChance;
  final double discoveryDistanceM;
  final String? explanation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pairs = <AerialReconStatPair>[
      AerialReconStatPair('Speed', _formatKmh(flightSpeedKmh)),
      AerialReconStatPair('Range', _formatKm(maxRouteKm)),
      AerialReconStatPair('Discover', _formatChance(discoveryChance)),
      AerialReconStatPair('Distance', _formatMeters(discoveryDistanceM)),
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
          height: 1.3,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (explanation != null && explanation!.isNotEmpty) ...[
          Text(explanation!, style: mutedStyle),
          const SizedBox(height: 10),
        ],
        AerialReconStatRow(pairs: pairs),
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

/// Mission summary: Length · Duration · Left/Ended · Sites (labeled, 4 per row).
class AerialReconMissionSummaryLine extends StatelessWidget {
  const AerialReconMissionSummaryLine({
    super.key,
    required this.mission,
  });

  final AerialReconMission mission;

  @override
  Widget build(BuildContext context) {
    final time = _timePair(mission);
    return AerialReconStatRow(
      pairs: [
        AerialReconStatPair(
          'Length',
          '${mission.routeLengthKm.toStringAsFixed(1)} km',
        ),
        AerialReconStatPair('Duration', _durationValue(mission)),
        AerialReconStatPair(time.label, time.value),
        AerialReconStatPair('Sites', '${mission.discoveredSiteCount}'),
      ],
    );
  }

  static String _durationValue(AerialReconMission mission) {
    final durationMin = (mission.flightDurationS / 60).round();
    if (durationMin <= 1) return '${mission.flightDurationS}s';
    return '$durationMin min';
  }

  static AerialReconStatPair _timePair(AerialReconMission mission) {
    if (mission.isFlying && mission.flightEndsAt != null) {
      final left = mission.flightEndsAt!.difference(DateTime.now().toUtc());
      if (left.isNegative) {
        return const AerialReconStatPair('Left', 'finishing…');
      }
      final mins = left.inMinutes;
      if (mins < 1) return const AerialReconStatPair('Left', '<1 min');
      return AerialReconStatPair('Left', '$mins min');
    }
    if (mission.isEnsuring) {
      return const AerialReconStatPair('Left', 'preparing…');
    }
    if (mission.status == 'cancelled') {
      final ended = mission.flightEndsAt ?? mission.createdAt;
      return AerialReconStatPair('Ended', _shortWhen(ended));
    }
    final ended = mission.flightEndsAt ?? mission.createdAt;
    return AerialReconStatPair('Ended', _shortWhen(ended));
  }

  static String _shortWhen(DateTime utc) {
    final local = utc.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${local.month}/${local.day}';
  }
}

/// Four equal labeled cells in one row.
class AerialReconStatRow extends StatelessWidget {
  const AerialReconStatRow({super.key, required this.pairs});

  final List<AerialReconStatPair> pairs;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final labelStyle = cardTheme.sectionLabelStyle(fontSize: 7);
    final valueStyle = cardTheme.bodyStyle(fontSize: 11).copyWith(
          fontWeight: FontWeight.w600,
          height: 1.15,
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < pairs.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pairs[i].label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
                const SizedBox(height: 2),
                Text(
                  pairs[i].value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: valueStyle,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class AerialReconStatPair {
  const AerialReconStatPair(this.label, this.value);

  final String label;
  final String value;
}
