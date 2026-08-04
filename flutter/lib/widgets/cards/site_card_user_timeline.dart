import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/aerial_session_controller.dart';
import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/relative_time.dart';
import '../common/app_toast.dart';
import 'card_section_panel.dart';

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
  const SiteCardUserTimeline({super.key, required this.site});

  final SiteSummary site;

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
      final aerial = (how == SiteSummary.howDiscoveredAerialRecon ||
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

    final identified = site.viewerHasIdentified == true ||
        site.identifiedAt != null ||
        site.status?.trim().toLowerCase() == 'identified';
    if (identified) {
      final identifiedAt = site.identifiedAt;
      entries.add(
        SiteTimelineEntry(
          moment: 'Identified',
          whenLabel: identifiedAt != null
              ? formatRelativeWhen(identifiedAt)
              : '—',
          howLabel: '—',
        ),
      );
    }

    final documented = site.documented == true ||
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

    return CardSectionPanel(
      label: 'Timeline',
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      labelGap: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            _EntryRow(entry: entries[i]),
          ],
        ],
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

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final SiteTimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final body = cardTheme.bodyStyle(fontSize: 11);
    final howStyle = entry.onHowTap != null
        ? body.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: Theme.of(context).colorScheme.primary,
          )
        : body;

    return Text.rich(
      TextSpan(
        style: body,
        children: [
          TextSpan(text: entry.moment),
          const TextSpan(text: ' · '),
          TextSpan(text: entry.whenLabel),
          if (entry.wasFirst && entry.howLabel != 'First') ...[
            const TextSpan(text: ' · '),
            const TextSpan(text: 'First'),
          ],
          if (entry.howLabel.isNotEmpty) ...[
            const TextSpan(text: ' · '),
            if (entry.onHowTap == null)
              TextSpan(text: entry.howLabel, style: howStyle)
            else
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: GestureDetector(
                  onTap: entry.onHowTap,
                  behavior: HitTestBehavior.opaque,
                  child: Text(entry.howLabel, style: howStyle),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
