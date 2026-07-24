import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/aerial_recon_controller.dart';
import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import 'card_section_panel.dart';

/// A single moment on a site's user-relation timeline.
class SiteTimelineEntry {
  const SiteTimelineEntry({
    required this.moment,
    required this.whenLabel,
    required this.howLabel,
    this.onHowTap,
  });

  final String moment;
  final String whenLabel;
  final String howLabel;
  final VoidCallback? onHowTap;
}

/// Compact table of user moments for a site (discovery first; more later).
class SiteCardUserTimeline extends StatelessWidget {
  const SiteCardUserTimeline({super.key, required this.site});

  final SiteSummary site;

  static List<SiteTimelineEntry> entriesFor(
    SiteSummary site, {
    VoidCallback? onAerialTap,
  }) {
    final discoveredAt = site.discoveredAt;
    final how = site.howDiscovered;
    if (discoveredAt == null && (how == null || how.isEmpty)) {
      return const [];
    }
    final aerial = how == SiteSummary.howDiscoveredAerialRecon &&
        site.discoveringMissionId != null;
    return [
      SiteTimelineEntry(
        moment: 'Discovered',
        whenLabel: discoveredAt != null
            ? formatRelativeWhen(discoveredAt)
            : '—',
        howLabel: howDiscoveredLabel(how),
        onHowTap: aerial ? onAerialTap : null,
      ),
    ];
  }

  static String howDiscoveredLabel(String? how) {
    switch (how) {
      case SiteSummary.howDiscoveredWalk:
        return 'Walk';
      case SiteSummary.howDiscoveredAerialRecon:
        return 'Aerial recon';
      case SiteSummary.howDiscoveredManual:
        return 'Manual';
      default:
        return how?.isNotEmpty == true ? how! : '—';
    }
  }

  static String formatRelativeWhen(DateTime utc) {
    final local = utc.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${local.month}/${local.day}/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final entries = entriesFor(
      site,
      onAerialTap: site.discoveringMissionId == null
          ? null
          : () => _focusAerial(context, site.discoveringMissionId!),
    );
    if (entries.isEmpty) return const SizedBox.shrink();

    final cardTheme = DinoCardTheme.of(context);

    return CardSectionPanel(
      label: 'Timeline',
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        children: [
          _HeaderRow(style: cardTheme.sectionLabelStyle(fontSize: 8)),
          const SizedBox(height: 4),
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            _EntryRow(entry: entries[i]),
          ],
        ],
      ),
    );
  }

  Future<void> _focusAerial(BuildContext context, int missionId) async {
    final recon = Provider.of<AerialReconController>(context, listen: false);
    final ok = await recon.focusMissionById(missionId);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not find that recon flight')),
      );
      return;
    }
    // Close site sheet / dialog if presented as a modal.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.style});

  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 3, child: Text('MOMENT', style: style)),
        Expanded(flex: 3, child: Text('WHEN', style: style)),
        Expanded(flex: 4, child: Text('HOW', style: style)),
      ],
    );
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: Text(entry.moment, style: body)),
        Expanded(flex: 3, child: Text(entry.whenLabel, style: body)),
        Expanded(
          flex: 4,
          child: entry.onHowTap == null
              ? Text(entry.howLabel, style: howStyle)
              : GestureDetector(
                  onTap: entry.onHowTap,
                  behavior: HitTestBehavior.opaque,
                  child: Text(entry.howLabel, style: howStyle),
                ),
        ),
      ],
    );
  }
}
