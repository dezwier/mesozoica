import 'package:flutter/material.dart';

import '../../models/tool.dart';
import '../../models/tool_session.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/relative_time.dart';
import '../common/chrome_action_button.dart';
import 'card_accordion_layout.dart';
import 'card_back_backdrop.dart';
import 'card_section_panel.dart';
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
              showScientificSubtitle: true,
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            top: 108,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CardAccordionLayout(
                    initialIndex: 0,
                    items: [
                      // Element 0: Tool parameters
                      CardAccordionItem(
                        builder: (context, isOpen, curvedT, lerpFn) {
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
                                            child: statsChild ??
                                                Text(
                                                  'Standard settings',
                                                  style: cardTheme.bodyStyle(fontSize: 12).copyWith(
                                                        color: cardTheme.cardTextMuted,
                                                      ),
                                                ),
                                          ),
                                          if (editButton != null)
                                            Positioned(top: 2, right: 2, child: editButton),
                                        ],
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          );
                        },
                      ),
                      // Element 1: Tool timeline history
                      CardAccordionItem(
                        builder: (context, isOpen, curvedT, lerpFn) {
                          return CardSectionPanel(
                            labelWidget: Text(
                              'Tool timeline history'.toUpperCase(),
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
                                      child: _HistoryList(
                                        history: history,
                                        loading: historyLoading,
                                        onHistoryTap: onHistoryTap,
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
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
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
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
        height: 22,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (history.isEmpty) {
      return Center(
        child: Text(
          'No history yet',
          style: cardTheme
              .bodyStyle(fontSize: 12)
              .copyWith(color: cardTheme.cardTextMuted),
        ),
      );
    }

    final divider = Divider(
      height: 1,
      thickness: 0.5,
      color: cardTheme.cardTextMuted.withValues(alpha: 0.22),
    );
    return ListView.separated(
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: history.length,
      separatorBuilder: (_, _) => divider,
      itemBuilder: (context, i) {
        return _HistoryRow(
          entry: history[i],
          onTap: onHistoryTap == null || history[i].session == null
              ? null
              : () => onHistoryTap!(history[i].session!),
        );
      },
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
    final primary = cardTheme.bodyStyle(fontSize: 11);
    final muted = primary.copyWith(color: cardTheme.cardTextMuted);
    final when = formatRelativeWhen(entry.at);

    if (entry.isRole) {
      final label = _roleLabel(entry.roleAction);
      return SizedBox(
        height: 22,
        child: Row(
          children: [
            Text(when, style: muted, maxLines: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Text('·', style: muted),
            ),
            Text(
              label,
              style: primary.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

    final row = SizedBox(
      height: 22,
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
              fontSize: 10,
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
