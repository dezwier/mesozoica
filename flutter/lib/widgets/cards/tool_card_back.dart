import 'package:flutter/material.dart';

import '../../models/tool.dart';
import '../../models/tool_session.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/relative_time.dart';
import '../common/chrome_action_button.dart';
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
    this.statsChild,
    this.ongoingChild,
    this.uses = const [],
    this.usesLoading = false,
    this.remainingDurationS,
    this.onUseTap,
  });

  final ToolSummary tool;
  final double titleFontSize;
  final double subtitleFontSize;
  final VoidCallback? onAction;
  final VoidCallback? onEditParams;
  final bool showActionButtons;

  /// Replaces the Rarity panel when non-null (e.g. deploy stats).
  final Widget? statsChild;

  /// Optional ongoing-session panel below stats.
  final Widget? ongoingChild;

  /// Compact use history (newest first).
  final List<ToolSession> uses;
  final bool usesLoading;
  final int? remainingDurationS;
  final ValueChanged<ToolSession>? onUseTap;

  static const double _actionHeight = 44;

  @override
  Widget build(BuildContext context) {
    final remaining = remainingDurationS ?? tool.remainingDurationS;
    final actionEnabled =
        tool.isOwned && onAction != null && (remaining == null || remaining > 0);
    final middle =
        statsChild ??
        CardSectionPanel(
          label: 'Rarity',
          child: _RarityRow(rarity: tool.rarity),
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
              centered: true,
              overlayOnImage: true,
              subtitleOverride: tool.inventoryBackSubtitle(),
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
                Stack(
                  children: [
                    middle,
                    if (onEditParams != null)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: IconButton(
                          onPressed: onEditParams,
                          icon: const Icon(Icons.settings, size: 18),
                          tooltip: 'Edit parameters',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: CardSectionPanel(
                    label: 'Uses',
                    expandChild: true,
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                    child: _UsesList(
                      uses: uses,
                      loading: usesLoading,
                      onUseTap: onUseTap,
                    ),
                  ),
                ),
                if (ongoingChild != null) ...[
                  const SizedBox(height: 8),
                  ongoingChild!,
                ],
                if (showActionButtons) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: _actionHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ChromeActionButton(
                            label: tool.action,
                            onPressed: actionEnabled ? onAction : null,
                          ),
                        ),
                        if (remaining != null) ...[
                          const SizedBox(width: 8),
                          Center(
                            child: Text(
                              _formatRemaining(remaining),
                              style: DinoCardTheme.of(context).bodyStyle(
                                fontSize: 13,
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
    if (seconds <= 0) return '0m left';
    final mins = (seconds + 59) ~/ 60;
    if (mins < 60) return '${mins}m left';
    final h = mins ~/ 60;
    final m = mins % 60;
    if (m == 0) return '${h}h left';
    return '${h}h ${m}m left';
  }
}

class _UsesList extends StatelessWidget {
  const _UsesList({
    required this.uses,
    required this.loading,
    this.onUseTap,
  });

  final List<ToolSession> uses;
  final bool loading;
  final ValueChanged<ToolSession>? onUseTap;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    if (loading && uses.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (uses.isEmpty) {
      return Text(
        'No uses yet',
        style: cardTheme.bodyStyle(fontSize: 12).copyWith(
              color: cardTheme.cardTextMuted,
            ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: uses.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        thickness: 0.5,
        color: cardTheme.cardTextMuted.withValues(alpha: 0.22),
      ),
      itemBuilder: (context, index) {
        final use = uses[index];
        return _UseRow(
          use: use,
          onTap: onUseTap == null ? null : () => onUseTap!(use),
        );
      },
    );
  }
}

class _UseRow extends StatelessWidget {
  const _UseRow({required this.use, this.onTap});

  final ToolSession use;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final primary = cardTheme.bodyStyle(fontSize: 11);
    final muted = primary.copyWith(color: cardTheme.cardTextMuted);
    final when = formatRelativeWhen(use.startedAt);
    final dur = _formatDuration(use.durationS);
    final status = _statusLabel(use);
    final discovered = use.discoveredCount;
    final result = discovered > 0
        ? '$discovered site${discovered == 1 ? '' : 's'}'
        : null;

    final statusColor = use.isActive
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
              fontWeight: use.isActive ? FontWeight.w600 : FontWeight.w400,
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

  static String _statusLabel(ToolSession use) {
    if (use.isActive) return 'live';
    if (use.isManualStop) return 'stopped';
    if (use.isExhausted) return 'done';
    if (use.stopReason == 'failed') return 'failed';
    return use.status;
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

class _RarityRow extends StatelessWidget {
  const _RarityRow({required this.rarity});

  final int rarity;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final clamped = rarity.clamp(1, 5);

    return Row(
      children: [
        ...List.generate(5, (index) {
          final filled = index < clamped;
          return Padding(
            padding: EdgeInsets.only(right: index == 4 ? 0 : 4),
            child: Icon(
              filled ? Icons.star : Icons.star_border,
              size: 18,
              color: filled ? cardTheme.cardAccent : cardTheme.cardTextMuted,
            ),
          );
        }),
        const SizedBox(width: 8),
        Text('$clamped/5', style: cardTheme.bodyStyle(fontSize: 13)),
      ],
    );
  }
}
