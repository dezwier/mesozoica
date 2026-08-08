import 'package:flutter/material.dart';

import '../../models/tool.dart';
import '../../models/tool_session.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/relative_time.dart';
import '../common/chrome_action_button.dart';
import 'card_accordion_layout.dart';
import 'card_attribute_grid.dart';
import 'card_back_backdrop.dart';
import 'card_section_panel.dart';
import 'card_timeline_history.dart';
import 'tool_card_header.dart';
import 'tool_card_image.dart';

class ToolCardBack extends StatelessWidget {
  const ToolCardBack({
    super.key,
    required this.tool,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
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

    final cardTheme = DinoCardTheme.of(context);
    final titleStyle = cardTheme.sectionLabelStyle(fontSize: 8.5).copyWith(
          color: cardTheme.cardTextSecondary,
          letterSpacing: 0.8,
          fontWeight: FontWeight.bold,
        );

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CardBackBackdrop(image: ToolCardImage(imageUrl: tool.mainImageUrl)),
          Positioned(
            left: 18,
            right: 18,
            top: 20,
            child: ToolCardHeader(
              tool: tool,
              titleFontSize: titleFontSize,
              subtitleFontSize: subtitleFontSize,
              overlayOnImage: true,
              showSkillBadge: true,
              showScientificSubtitle: false, // Drop subtitle for tool cards
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            top: 72, // Align the top offset of the accordion layout to exactly 72
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CardAccordionLayout(
                    initialIndex: 0,
                    items: [
                      // Element 0: Tool parameters (generalized CardAttributeGrid)
                      CardAccordionItem(
                        builder: (context, isOpen, curvedT, lerpFn) {
                          final params = tool.isOwned && tool.params.isNotEmpty ? tool.params : tool.baseParams;
                          final formatted = _formatToolParams(params);
                          return CardSectionPanel(
                            labelWidget: Text(
                              'Tool parameters'.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: titleStyle,
                            ),
                            labelGap: 6,
                            expandChild: true,
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                            child: isOpen
                                ? FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.center,
                                    child: SizedBox(
                                      height: 112,
                                      width: 340,
                                      child: Stack(
                                        children: [
                                          Center(
                                            child: CardAttributeGrid(
                                              attributes: [
                                                for (final entry in formatted.entries)
                                                  CardAttributeItem(entry.key, entry.value),
                                              ],
                                              isOpen: isOpen,
                                            ),
                                          ),
                                          if (editButton != null)
                                            Positioned(top: 2, right: 2, child: editButton),
                                        ],
                                      ),
                                    ),
                                  )
                                : FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.center,
                                    child: SizedBox(
                                      height: 22,
                                      width: 340,
                                      child: Stack(
                                        children: [
                                          Center(
                                            child: CardAttributeGrid(
                                              attributes: [
                                                for (final entry in formatted.entries)
                                                  CardAttributeItem(entry.key, entry.value),
                                              ],
                                              isOpen: isOpen,
                                            ),
                                          ),
                                          if (editButton != null)
                                            Positioned(top: 2, right: 2, child: editButton),
                                        ],
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
                      // Element 1: Tool timeline history (generalized CardTimelineHistory)
                      CardAccordionItem(
                        builder: (context, isOpen, curvedT, lerpFn) {
                          final events = [
                            for (final entry in history)
                              CardTimelineEvent(
                                status: entry.isRole
                                    ? (entry.roleAction == 'owned' ? 'Obtained' : 'Role change')
                                    : 'Used',
                                when: formatRelativeWhen(entry.at),
                                detail: entry.isRole
                                    ? null
                                    : (entry.session != null
                                        ? '${_HistoryRow._formatDuration(entry.session!.durationS)} · ${_HistoryRow._statusLabel(entry.session!)}'
                                        : null),
                                isHighlight: entry.isRole || (entry.session?.isActive == true),
                              ),
                          ];

                          return CardSectionPanel(
                            labelWidget: Text(
                              'Tool timeline history'.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: titleStyle,
                            ),
                            labelGap: 6,
                            expandChild: true,
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: SizedBox(
                                height: isOpen ? 112 : 22,
                                width: 340,
                                child: CardTimelineHistory(
                                  events: events,
                                  isOpen: isOpen,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                if (showActionButtons) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: _actionHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ChromeActionButton(
                            label: actionLabel,
                            onPressed: actionEnabled ? onAction : null,
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
                                    color: const Color(0xFFF0EBE3),
                                    shadows: const [
                                      Shadow(
                                        color: Color(0x99000000),
                                        blurRadius: 4,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
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

  static Map<String, String> _formatToolParams(Map<String, dynamic> params) {
    final out = <String, String>{};
    for (final entry in params.entries) {
      final key = entry.key;
      if (key == 'stats_explanation' || key == 'modifies_main_params') continue;

      final value = entry.value;
      final label = _humanizeKey(key);

      // Format value
      String valueStr = '';
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
          valueStr = value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
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
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, this.onTap});

  final ToolHistoryEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink(); // Legacy row not used anymore inside history, but kept for method accesses or backward compatibility
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
