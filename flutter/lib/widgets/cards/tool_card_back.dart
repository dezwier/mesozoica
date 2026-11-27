import 'package:flutter/material.dart';

import '../../models/tool.dart';
import '../../models/tool_session.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/relative_time.dart';
import '../common/chrome_action_button.dart';
import 'card_attribute_grid.dart';
import 'card_back_body.dart';
import 'card_history_drawer.dart';
import 'museum_card_frame.dart';
import 'museum_card_icons.dart';
import 'tool_card_header.dart';
import 'tool_card_image.dart';

class ToolCardBack extends StatelessWidget {
  const ToolCardBack({
    super.key,
    required this.tool,
    this.titleFontSize = 28,
    this.subtitleFontSize = 12,
    this.onAction,
    this.onEditParams,
    this.showActionButtons = true,
    this.inUse = false,
    this.statsChild,
    this.history = const [],
    this.historyLoading = false,
    this.remainingDurationS,
    this.onHistoryTap,
  });

  final ToolSummary tool;
  final double titleFontSize;
  final double subtitleFontSize;
  final VoidCallback? onAction;
  final VoidCallback? onEditParams;
  final bool showActionButtons;

  /// True when this occurrence already has a live session.
  final bool inUse;

  /// Optional deploy/stats panel above History (e.g. tool action knobs).
  final Widget? statsChild;

  /// Compact card history: uses + role changes, newest first.
  final List<ToolHistoryEntry> history;
  final bool historyLoading;
  final int? remainingDurationS;
  final ValueChanged<ToolSession>? onHistoryTap;

  static const double _actionHeight = 44;

  void _openHistory(BuildContext context) {
    CardHistoryDrawer.show(
      context,
      title: 'History',
      child: ToolCardHistoryList(
        history: history,
        loading: historyLoading,
        onHistoryTap: onHistoryTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remaining = remainingDurationS ?? tool.remainingDurationS;
    final actionEnabled =
        !inUse &&
        tool.isOwned &&
        onAction != null &&
        (remaining == null || remaining > 0);
    final actionLabel = inUse ? 'In use' : tool.action;
    final editButton = onEditParams == null
        ? null
        : IconButton(
            onPressed: onEditParams,
            icon: const Icon(Icons.settings, size: 18),
            tooltip: 'Edit parameters',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          );

    final params = tool.isOwned && tool.params.isNotEmpty
        ? tool.params
        : tool.baseParams;
    final formatted = _formatToolParams(params);

    final actionRow = showActionButtons
        ? SizedBox(
            height: _actionHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ChromeActionButton(
                    label: actionLabel,
                    onPressed: actionEnabled ? onAction : null,
                    labelStyle: const TextStyle(
                      fontFamily: DinoCardTheme.titleFontFamily,
                    ),
                  ),
                ),
                if (remaining != null) ...[
                  const SizedBox(width: 8),
                  Center(
                    child: Text(
                      _formatRemaining(remaining),
                      style: DinoCardTheme.of(context)
                          .bodyStyle(fontSize: 13)
                          .copyWith(
                            fontFamily: DinoCardTheme.titleFontFamily,
                            color: DinoCardTheme.of(context).museumTitleColor,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ],
            ),
          )
        : null;

    return MuseumCardFrame(
      image: ToolCardImage(imageUrl: tool.mainImageUrl),
      emblem: MuseumGlyph.tool,
      title: tool.name,
      titleFontSize: titleFontSize,
      subtitleFontSize: subtitleFontSize,
      trailing: tool.skillId == null
          ? null
          : ToolSkillBadge(tool: tool, size: 34),
      bottom: actionRow,
      panels: CardBackSection(
        title: 'Parameters',
        expandChild: true,
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CardAttributeGrid(
                    attributes: [
                      for (final entry in formatted.entries)
                        CardAttributeItem(entry.key, entry.value),
                    ],
                  ),
                  if (statsChild != null) ...[
                    const SizedBox(height: 8),
                    statsChild!,
                  ],
                ],
              ),
            ),
            if (editButton != null)
              Positioned(top: 0, right: 0, child: editButton),
          ],
        ),
      ),
      onHistory: () => _openHistory(context),
    );
  }

  static Map<String, String> _formatToolParams(Map<String, dynamic> params) {
    final out = <String, String>{};
    for (final entry in params.entries) {
      final key = entry.key;
      if (key == 'stats_explanation' || key == 'modifies_main_params') continue;

      final value = entry.value;
      final label = _humanizeKey(key);

      var valueStr = '';
      if (value is num) {
        if (key.endsWith('_kmh')) {
          valueStr = '${value.toStringAsFixed(0)} km/h';
        } else if (key.endsWith('_m')) {
          valueStr = '${value.toStringAsFixed(0)}m';
        } else if (key.endsWith('_minutes')) {
          valueStr = '$value min';
        } else if (key.endsWith('_chance')) {
          valueStr = '${(value * 100).toStringAsFixed(0)}%';
        } else {
          valueStr = value == value.roundToDouble()
              ? value.toStringAsFixed(0)
              : value.toStringAsFixed(1);
        }
      } else {
        valueStr = value?.toString() ?? '—';
      }
      out[label] = valueStr;
    }
    return out;
  }

  static String _humanizeKey(String key) {
    return key
        .split('_')
        .where((p) => p.isNotEmpty)
        .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
        .join(' ');
  }

  static String _formatRemaining(int seconds) {
    if (seconds <= 0) return '0s left';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s left';
    if (m > 0) return '${m}m ${s}s left';
    return '${s}s left';
  }
}

class ToolCardHistoryList extends StatelessWidget {
  const ToolCardHistoryList({
    super.key,
    required this.history,
    required this.loading,
    this.onHistoryTap,
  });

  final List<ToolHistoryEntry> history;
  final bool loading;
  final ValueChanged<ToolSession>? onHistoryTap;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    if (loading && history.isEmpty) {
      return const SizedBox(
        height: 40,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (history.isEmpty) {
      return Text(
        'No history yet',
        style: cardTheme
            .bodyStyle(fontSize: 14)
            .copyWith(color: cardTheme.cardTextMuted),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < history.length; i++) ...[
          if (i > 0)
            Divider(
              height: 12,
              thickness: 0.5,
              color: cardTheme.cardTextMuted.withValues(alpha: 0.22),
            ),
          _HistoryRow(
            entry: history[i],
            onTap: onHistoryTap == null || history[i].session == null
                ? null
                : () => onHistoryTap!(history[i].session!),
          ),
        ],
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, this.onTap});

  final ToolHistoryEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final primary = cardTheme.bodyStyle(fontSize: 13);
    final muted = primary.copyWith(color: cardTheme.cardTextMuted);
    final when = formatRelativeWhen(entry.at);

    if (entry.isRole) {
      final label = _roleLabel(entry.roleAction);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text(when, style: muted, maxLines: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Text('·', style: muted),
            ),
            Flexible(
              child: Text(
                label,
                style: primary.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    final session = entry.session;
    if (session == null) return const SizedBox.shrink();

    final dur = _formatDuration(session.durationS);
    final status = _statusLabel(session);
    final discovered = session.discoveredCount;
    final result = discovered > 0
        ? '$discovered site${discovered == 1 ? '' : 's'}'
        : null;

    final statusColor = session.isActive
        ? cardTheme.cardAccent
        : cardTheme.cardTextMuted;

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(when, style: muted, maxLines: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text('·', style: muted),
          ),
          Text(dur, style: primary.copyWith(fontWeight: FontWeight.w600)),
          if (result != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Text('·', style: muted),
            ),
            Flexible(
              child: Text(
                result,
                style: muted,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else
            const Spacer(),
          const SizedBox(width: 8),
          Text(
            status,
            style: muted.copyWith(
              color: statusColor,
              fontWeight: session.isActive ? FontWeight.w600 : FontWeight.w400,
              fontSize: 11,
              letterSpacing: 0.3,
            ),
            maxLines: 1,
          ),
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: row,
    );
  }

  static String _roleLabel(String? action) {
    switch (action) {
      case 'owned':
        return 'Obtained';
      case null:
      case '':
        return 'Role change';
      default:
        if (action.isEmpty) return 'Role change';
        return '${action[0].toUpperCase()}${action.substring(1)}';
    }
  }

  static String _statusLabel(ToolSession session) {
    if (session.isActive) return 'live';
    if (session.isManualStop) return 'stopped';
    if (session.isExhausted) return 'done';
    if (session.stopReason == 'failed') return 'failed';
    return session.status;
  }

  static String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final mins = (seconds / 60).round();
    if (mins < 60) return '${mins}m';
    final h = mins ~/ 60;
    final m = mins % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}
