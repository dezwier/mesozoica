import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/aerial_session_controller.dart';
import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/relative_time.dart';
import '../common/app_toast.dart';
import 'card_section_panel.dart';
import 'card_timeline_history.dart';

/// A single moment on a site's user-relation timeline.
class SiteTimelineEntry {
  const SiteTimelineEntry({
    required this.moment,
    required this.whenLabel,
    required this.howLabel,
    this.wasFirst = false,
    this.onHowTap,
  });

  final String moment;
  final String whenLabel;
  final String howLabel;
  final bool wasFirst;
  final VoidCallback? onHowTap;
}

/// Compact list of user moments for a site (discovery / documentation).
class SiteCardUserTimeline extends StatelessWidget {
  const SiteCardUserTimeline({
    super.key,
    required this.site,
    this.isOpen = true,
    this.height,
  });

  final SiteSummary site;
  final bool isOpen;
  final double? height;

  static List<SiteTimelineEntry> entriesFor(
    SiteSummary site, {
    VoidCallback? onAerialTap,
  }) {
    final entries = <SiteTimelineEntry>[];
    final discoveredAt = site.discoveredAt;
    final how = site.howDiscovered;
    final hasDiscovery =
        discoveredAt != null || (how != null && how.isNotEmpty);
    if (hasDiscovery) {
      final aerial =
          (how == SiteSummary.howDiscoveredAerialRecon ||
              how == SiteSummary.howDiscoveredAerialScout) &&
          site.discoveringSessionId != null;
      entries.add(
        SiteTimelineEntry(
          moment: 'Discovered',
          whenLabel: discoveredAt != null
              ? formatRelativeWhen(discoveredAt)
              : '—',
          howLabel: howDiscoveredLabel(how),
          wasFirst: site.viewerWasFirstDiscovery == true,
          onHowTap: aerial ? onAerialTap : null,
        ),
      );
    }

    final documented =
        site.documented == true ||
        site.viewerHasDocumented == true ||
        site.documentedAt != null;
    if (documented) {
      final documentedAt = site.documentedAt ?? discoveredAt;
      final wasFirst = site.viewerWasFirstDocumentation == true;
      entries.add(
        SiteTimelineEntry(
          moment: 'Documented',
          whenLabel: documentedAt != null
              ? formatRelativeWhen(documentedAt)
              : '—',
          howLabel: wasFirst ? 'First' : '—',
          wasFirst: wasFirst,
        ),
      );
    }

    return entries;
  }

  static String howDiscoveredLabel(String? how) {
    switch (how) {
      case SiteSummary.howDiscoveredWalk:
        return 'Walk';
      case SiteSummary.howDiscoveredAerialRecon:
        return 'Aerial recon';
      case SiteSummary.howDiscoveredAerialScout:
        return 'Aerial scout';
      case SiteSummary.howDiscoveredManual:
        return 'Manual';
      default:
        return how?.isNotEmpty == true ? how! : '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = entriesFor(
      site,
      onAerialTap: site.discoveringSessionId == null
          ? null
          : () => _focusAerial(context, site.discoveringSessionId!),
    );
    if (entries.isEmpty) return const SizedBox.shrink();

    // Reversing so latest is first
    final events = [
      for (final entry in entries.reversed)
        CardTimelineEvent(
          status: entry.moment,
          when: entry.whenLabel,
          detail: entry.howLabel != '—' ? entry.howLabel : null,
          isHighlight: entry.moment == 'Documented',
        ),
    ];

    final cardTheme = DinoCardTheme.of(context);
    final titleStyle = cardTheme.sectionLabelStyle(fontSize: 8.5).copyWith(
          color: cardTheme.cardTextSecondary,
          letterSpacing: 0.8,
          fontWeight: FontWeight.bold,
        );

    final double resolvedHeight = height ?? (isOpen ? 44.0 : 22.0);

    return CardSectionPanel(
      labelWidget: Text(
        'Site history timeline'.toUpperCase(),
        textAlign: TextAlign.center,
        style: titleStyle,
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      labelGap: 6,
      expandChild: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: CardTimelineHistory(
          events: events,
          isOpen: isOpen,
        ),
      ),
    );
  }

  Future<void> _focusAerial(BuildContext context, int sessionId) async {
    final recon = Provider.of<AerialSessionController>(context, listen: false);
    final ok = await recon.focusSessionById(sessionId);
    if (!context.mounted) return;
    if (!ok) {
      AppToast.warning(context, 'Could not find that recon flight');
      return;
    }
    // Close site sheet / dialog if presented as a modal.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }
}
