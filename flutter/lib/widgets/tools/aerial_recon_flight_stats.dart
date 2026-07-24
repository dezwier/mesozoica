import 'package:flutter/material.dart';

import '../../config/game_config.dart';
import '../../services/tool_service.dart';
import '../../theme/dino_card_theme.dart';

/// Shared display of aerial recon flight / deploy knobs (2 params per row).
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
    final pairs = <_StatPair>[
      _StatPair('Speed', _formatKmh(flightSpeedKmh)),
      _StatPair('Max range', _formatKm(maxRouteKm)),
      _StatPair('Discover', _formatChance(discoveryChance)),
      _StatPair('Distance', _formatMeters(discoveryDistanceM)),
    ];

    if (compact) {
      return Text(
        pairs.map((r) => '${r.label} ${r.value}').join(' · '),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final cardTheme = DinoCardTheme.of(context);
    final labelStyle = cardTheme.sectionLabelStyle(fontSize: 8);
    final valueStyle = cardTheme.bodyStyle(fontSize: 13).copyWith(
          fontWeight: FontWeight.w600,
        );
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
        for (var i = 0; i < pairs.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ParamCell(
                  pair: pairs[i],
                  labelStyle: labelStyle,
                  valueStyle: valueStyle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: i + 1 < pairs.length
                    ? _ParamCell(
                        pair: pairs[i + 1],
                        labelStyle: labelStyle,
                        valueStyle: valueStyle,
                      )
                    : const SizedBox.shrink(),
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

/// Status line: status · length · duration · time left/ended · sites found.
class AerialReconMissionSummaryLine extends StatelessWidget {
  const AerialReconMissionSummaryLine({
    super.key,
    required this.mission,
    this.style,
  });

  final AerialReconMission mission;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    return Text(
      format(mission),
      style: style ??
          cardTheme.bodyStyle(fontSize: 12).copyWith(
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
    );
  }

  /// status, length, duration, duration left (or ended), sites found.
  static String format(AerialReconMission mission) {
    final parts = <String>[
      statusLabel(mission.status),
      '${mission.routeLengthKm.toStringAsFixed(1)} km',
      durationLabel(mission),
      timeLeftOrEndedLabel(mission),
      sitesLabel(mission.discoveredSiteCount),
    ];
    return parts.join(' · ');
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'ensuring':
        return 'Preparing';
      case 'flying':
        return 'In flight';
      case 'done':
        return 'Completed';
      case 'failed':
        return 'Failed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  static String durationLabel(AerialReconMission mission) {
    final durationMin = (mission.flightDurationS / 60).round();
    if (durationMin <= 1) {
      return '${mission.flightDurationS}s';
    }
    return '$durationMin min';
  }

  static String timeLeftOrEndedLabel(AerialReconMission mission) {
    if (mission.isFlying && mission.flightEndsAt != null) {
      final left = mission.flightEndsAt!.difference(DateTime.now().toUtc());
      if (left.isNegative) return 'finishing…';
      final mins = left.inMinutes;
      if (mins < 1) return '<1 min left';
      return '$mins min left';
    }
    if (mission.isEnsuring) return 'preparing…';
    if (mission.status == 'cancelled') {
      final ended = mission.flightEndsAt ?? mission.createdAt;
      return 'stopped ${_shortWhen(ended)}';
    }
    final ended = mission.flightEndsAt ?? mission.createdAt;
    return 'ended ${_shortWhen(ended)}';
  }

  static String sitesLabel(int count) {
    return count == 1 ? '1 site' : '$count sites';
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

class _ParamCell extends StatelessWidget {
  const _ParamCell({
    required this.pair,
    required this.labelStyle,
    required this.valueStyle,
  });

  final _StatPair pair;
  final TextStyle labelStyle;
  final TextStyle valueStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(pair.label.toUpperCase(), style: labelStyle),
        const SizedBox(height: 2),
        Text(pair.value, style: valueStyle),
      ],
    );
  }
}

class _StatPair {
  const _StatPair(this.label, this.value);

  final String label;
  final String value;
}
