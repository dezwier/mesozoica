import 'package:flutter/material.dart';

import '../../config/game_config.dart';
import '../../models/tool_session.dart';
import '../../theme/dino_card_theme.dart';
import '../tools/tool_stat_row.dart';

/// Shared display of aerial recon flight / deploy knobs (4 params per row).
class AerialFlightStats extends StatelessWidget {
  const AerialFlightStats({
    super.key,
    required this.flightSpeedKmh,
    required this.durationMinutes,
    required this.discoveryChance,
    required this.discoveryDistanceM,
    this.explanation,
    this.compact = false,
  });

  /// From current [GameConfig] (deploy-now stats).
  factory AerialFlightStats.fromConfig({
    Key? key,
    String actionKey = 'aerial_recon',
    bool compact = false,
    bool includeExplanation = true,
  }) {
    final cfg = GameConfig.instance.toolActions.configFor(actionKey);
    return AerialFlightStats(
      key: key,
      flightSpeedKmh: cfg.flightSpeedKmh,
      durationMinutes: cfg.durationMinutes,
      discoveryChance: cfg.flightDiscoveryChance,
      discoveryDistanceM: cfg.flightDiscoveryDistanceM,
      explanation: includeExplanation ? cfg.statsExplanation : null,
      compact: compact,
    );
  }

  factory AerialFlightStats.fromParams(
    Map<String, dynamic> params, {
    Key? key,
    bool compact = false,
    bool includeExplanation = true,
  }) {
    final speed = (params['flight_speed_kmh'] as num?)?.toDouble() ?? 0;
    final duration = _durationMinutesFromParams(params, speed: speed);
    return AerialFlightStats(
      key: key,
      flightSpeedKmh: speed,
      durationMinutes: duration,
      discoveryChance:
          (params['flight_discovery_chance'] as num?)?.toDouble() ??
          (params['discovery_chance'] as num?)?.toDouble() ??
          0,
      discoveryDistanceM:
          (params['flight_discovery_distance_m'] as num?)?.toDouble() ??
          (params['discovery_distance_m'] as num?)?.toDouble() ??
          0,
      explanation: includeExplanation
          ? params['stats_explanation'] as String?
          : null,
      compact: compact,
    );
  }

  /// From a session snapshot (with config fallback for null knobs).
  ///
  /// Duration is the actual flight time from route length ÷ speed, not the
  /// tool's battery/budget [duration_minutes] param.
  factory AerialFlightStats.fromSession(
    ToolSession session, {
    Key? key,
    bool compact = false,
  }) {
    final cfg = GameConfig.instance.toolActions.configFor(session.actionKey);
    final speed = session.flightSpeedKmh ?? cfg.flightSpeedKmh;
    return AerialFlightStats(
      key: key,
      flightSpeedKmh: speed,
      durationMinutes: _minutesFromFlightSeconds(session.flightDurationS),
      discoveryChance:
          session.flightDiscoveryChance ?? cfg.flightDiscoveryChance,
      discoveryDistanceM:
          session.flightDiscoveryDistanceM ?? cfg.flightDiscoveryDistanceM,
      compact: compact,
    );
  }

  final double flightSpeedKmh;
  final int durationMinutes;
  final double discoveryChance;
  final double discoveryDistanceM;
  final String? explanation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pairs = <AerialFlightStatPair>[
      AerialFlightStatPair('Speed', _formatKmh(flightSpeedKmh)),
      AerialFlightStatPair('Duration', _formatDuration(durationMinutes)),
      AerialFlightStatPair('Flight chance', _formatChance(discoveryChance)),
      AerialFlightStatPair('Flight range', _formatMeters(discoveryDistanceM)),
    ];

    if (compact) {
      return Text(
        pairs.map((r) => '${r.label} ${r.value}').join(' · '),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final cardTheme = DinoCardTheme.of(context);
    final mutedStyle = cardTheme
        .bodyStyle(fontSize: 11)
        .copyWith(color: cardTheme.cardTextMuted, height: 1.3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (explanation != null && explanation!.isNotEmpty) ...[
          Text(explanation!, style: mutedStyle),
          const SizedBox(height: 10),
        ],
        ToolStatGrid(
          pairs: pairs.map((p) => ToolStatPair(p.label, p.value)).toList(),
        ),
      ],
    );
  }

  static int _durationMinutesFromParams(
    Map<String, dynamic> params, {
    required double speed,
  }) {
    final duration = (params['duration_minutes'] as num?)?.toInt();
    if (duration != null) return duration;
    final maxRoute = (params['max_route_km'] as num?)?.toDouble();
    if (maxRoute != null && speed > 0) {
      return (maxRoute / speed * 60).round();
    }
    return 0;
  }

  static int _minutesFromFlightSeconds(int seconds) {
    if (seconds <= 0) return 0;
    final minutes = (seconds / 60).round();
    return minutes < 1 ? 1 : minutes;
  }

  static String _formatKmh(double v) {
    final label = v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(1);
    return '$label km/h';
  }

  static String _formatDuration(int minutes) {
    if (minutes <= 0) return '—';
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rem = minutes % 60;
    if (rem == 0) return hours == 1 ? '1 hour' : '$hours hours';
    return '${hours}h ${rem}m';
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

/// Session summary: Length · Duration · Left/Ended · Sites (labeled, 4 per row).
class AerialSessionSummaryLine extends StatelessWidget {
  const AerialSessionSummaryLine({super.key, required this.session});

  final ToolSession session;

  @override
  Widget build(BuildContext context) {
    final time = _timePair(session);
    return ToolStatGrid(
      pairs: [
        ToolStatPair(
          'Length',
          '${session.routeLengthKm.toStringAsFixed(1)} km',
        ),
        ToolStatPair('Duration', _durationValue(session)),
        ToolStatPair(time.label, time.value),
        ToolStatPair('Sites found', '${session.discoveredSiteCount}'),
      ],
    );
  }

  static String _durationValue(ToolSession session) {
    final durationMin = (session.flightDurationS / 60).round();
    if (durationMin <= 1) return '${session.flightDurationS}s';
    return '$durationMin min';
  }

  static AerialFlightStatPair _timePair(ToolSession session) {
    if (session.isInFlight && session.flightEndsAt != null) {
      final left = session.flightEndsAt!.difference(DateTime.now().toUtc());
      if (left.isNegative) {
        return const AerialFlightStatPair('Left', 'finishing…');
      }
      final mins = left.inMinutes;
      if (mins < 1) return const AerialFlightStatPair('Left', '<1 min');
      return AerialFlightStatPair('Left', '$mins min');
    }
    if (session.isPending) {
      return const AerialFlightStatPair('Left', 'preparing…');
    }
    if (session.status == 'cancelled') {
      final ended =
          session.flightEndsAt ?? session.endedAt ?? session.startedAt;
      return AerialFlightStatPair('Ended', _shortWhen(ended));
    }
    final ended = session.flightEndsAt ?? session.endedAt ?? session.startedAt;
    return AerialFlightStatPair('Ended', _shortWhen(ended));
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
class AerialFlightStatRow extends StatelessWidget {
  const AerialFlightStatRow({super.key, required this.pairs});

  final List<AerialFlightStatPair> pairs;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final labelStyle = cardTheme.sectionLabelStyle(fontSize: 7);
    final valueStyle = cardTheme
        .bodyStyle(fontSize: 11)
        .copyWith(fontWeight: FontWeight.w600, height: 1.15);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < pairs.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  pairs[i].label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: labelStyle,
                ),
                const SizedBox(height: 2),
                Text(
                  pairs[i].value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
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

class AerialFlightStatPair {
  const AerialFlightStatPair(this.label, this.value);

  final String label;
  final String value;
}
