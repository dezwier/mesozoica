import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

class CardTimelineEvent {
  final String status;      // e.g., 'Discovered', 'Documented', 'Reconstructed', 'Obtained', 'Used'
  final String when;        // relative time string
  final String? detail;     // e.g., 'Walk', 'First', 'stopped', etc.
  final bool isHighlight;   // highlight style / badge color

  const CardTimelineEvent({
    required this.status,
    required this.when,
    this.detail,
    this.isHighlight = false,
  });
}

class CardTimelineHistory extends StatelessWidget {
  const CardTimelineHistory({
    super.key,
    required this.events,
    required this.isOpen,
  });

  final List<CardTimelineEvent> events;
  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    if (events.isEmpty) {
      return SizedBox(
        width: 340,
        child: Text(
          'No history yet',
          style: cardTheme.bodyStyle(fontSize: 13.0).copyWith(
                color: cardTheme.cardTextMuted,
              ),
        ),
      );
    }

    Widget content;
    if (!isOpen) {
      // Close mode: show latest status
      final latest = events.first;
      content = _EventRow(event: latest, isClosed: true);
    } else {
      // Open mode: visual timeline sequence with dots per event, line connecting dots
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < events.length; i++)
            _TimelineItemWidget(
              event: events[i],
              isFirst: i == 0,
              isLast: i == events.length - 1,
            ),
        ],
      );
    }

    return SizedBox(
      width: 340,
      child: content,
    );
  }
}

class _TimelineItemWidget extends StatelessWidget {
  const _TimelineItemWidget({
    required this.event,
    required this.isFirst,
    required this.isLast,
  });

  final CardTimelineEvent event;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Visual line and dot on the left with a fixed width
        SizedBox(
          width: 32,
          height: 36, // fixed height for visual item
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Vertical line
              Positioned(
                top: isFirst ? 18 : 0,
                bottom: isLast ? 18 : 0,
                child: Container(
                  width: 2,
                  color: cardTheme.cardAccent.withValues(alpha: 0.25),
                ),
              ),
              // Centered dot
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: event.isHighlight
                      ? cardTheme.cardAccent
                      : cardTheme.cardTextSecondary.withValues(alpha: 0.5),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.8),
                    width: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Event row centered vertically relative to the 36 height of the line
        Expanded(
          child: SizedBox(
            height: 36,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _EventRow(event: event, isClosed: false),
            ),
          ),
        ),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.isClosed,
  });

  final CardTimelineEvent event;
  final bool isClosed;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final fontSize = isClosed ? 13.0 : 12.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: isClosed ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        // Put time as first italic
        Text(
          event.when,
          style: cardTheme.bodyStyle(fontSize: fontSize).copyWith(
                fontStyle: FontStyle.italic,
                color: cardTheme.cardTextMuted,
              ),
        ),
        const SizedBox(width: 8),
        // Status in badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: event.isHighlight
                ? cardTheme.cardAccent.withValues(alpha: 0.15)
                : cardTheme.cardTextSecondary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: event.isHighlight
                  ? cardTheme.cardAccent.withValues(alpha: 0.5)
                  : cardTheme.cardTextSecondary.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: Text(
            event.status,
            style: cardTheme.statLabelStyle(fontSize: 8.5).copyWith(
                  fontWeight: FontWeight.bold,
                  color: event.isHighlight ? cardTheme.cardAccent : cardTheme.cardTextSecondary,
                ),
          ),
        ),
        if (event.detail != null && event.detail!.isNotEmpty) ...[
          const SizedBox(width: 8),
          if (event.detail!.contains(' · ')) ...[
            for (final part in event.detail!.split(' · ')) ...[
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  part,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: cardTheme.bodyStyle(fontSize: fontSize).copyWith(
                        fontWeight: FontWeight.w600,
                        color: cardTheme.cardTextPrimary,
                      ),
                ),
              ),
            ],
          ] else ...[
            Flexible(
              child: Text(
                event.detail!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: cardTheme.bodyStyle(fontSize: fontSize).copyWith(
                      fontWeight: FontWeight.w600,
                      color: cardTheme.cardTextPrimary,
                    ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
