import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/map_controller.dart' as map_data;
import '../../models/site.dart';
import '../../services/site_service.dart';
import '../../theme/dino_card_theme.dart';
import '../cards/card_detail_sheet.dart';
import '../cards/site_status_helper.dart';
import '../cards/site_turnable_card.dart';

Future<void> showSiteMapCardDialog(
  BuildContext context,
  SiteSummary site,
) {
  return CardDetailSheet.show<void>(
    context,
    builder: (context) => _SiteMapCardWithActions(site: site),
  );
}

class _SiteMapCardWithActions extends StatefulWidget {
  const _SiteMapCardWithActions({required this.site});

  final SiteSummary site;

  @override
  State<_SiteMapCardWithActions> createState() =>
      _SiteMapCardWithActionsState();
}

class _SiteMapCardWithActionsState extends State<_SiteMapCardWithActions> {
  late SiteSummary _site;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _site = widget.site;
  }

  void _onSiteUpdated(SiteSummary updated) {
    setState(() => _site = updated);
    context.read<map_data.MapController>().upsertSite(updated);
  }

  bool get _canSurvey {
    if (_busy) return false;
    if (_site.viewerHasSurveyed == true) return false;
    final status = _site.status?.trim().toLowerCase() ?? '';
    // Allow survey once the site is at least discovered for someone / linked.
    return status.isNotEmpty && status != 'hidden';
  }

  Future<void> _onSurvey() async {
    if (!_canSurvey) return;
    setState(() => _busy = true);
    final service = SiteService();
    try {
      final result = await service.surveySite(_site.siteId);
      if (!mounted) return;
      _onSiteUpdated(
        result.site.copyWith(viewerHasSurveyed: true),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Site surveyed.')),
      );
    } on SiteServiceException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not survey site. Try again.')),
        );
      }
    } finally {
      service.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onStatusAction(String status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final updated = await applySiteStatusSelection(
        context,
        _site,
        newStatus: status,
      );
      if (updated != null && mounted) {
        _onSiteUpdated(updated);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Matches card horizontal inset to the screen edge.
  static const double _edgeInset = 16;
  static const double _actionHeight = 50;
  static const double _actionGap = 6;

  @override
  Widget build(BuildContext context) {
    // Buttons sit fully below the card with [_edgeInset] gap, but are painted
    // behind the turnable card so they stay put while it flips.
    const actionClearance = _actionHeight + _edgeInset;

    return CardDetailSheetContent(
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: _edgeInset,
            right: _edgeInset,
            bottom: 0,
            height: _actionHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _MapSiteActionButton(
                    label: _site.viewerHasSurveyed == true
                        ? 'Surveyed'
                        : 'Survey',
                    onPressed: _canSurvey ? _onSurvey : null,
                  ),
                ),
                const SizedBox(width: _actionGap),
                Expanded(
                  child: _MapSiteActionButton(
                    label: 'Protect',
                    onPressed:
                        _busy ? null : () => _onStatusAction('protected'),
                  ),
                ),
                const SizedBox(width: _actionGap),
                Expanded(
                  child: _MapSiteActionButton(
                    label: 'Excavate',
                    onPressed:
                        _busy ? null : () => _onStatusAction('excavation'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: actionClearance),
            child: SiteTurnableCard(
              site: _site,
              onSiteUpdated: _onSiteUpdated,
              outerPadding: const EdgeInsets.fromLTRB(
                _edgeInset,
                8,
                _edgeInset,
                0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Neutral gray action button behind the map site card.
class _MapSiteActionButton extends StatelessWidget {
  const _MapSiteActionButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  static const Color _label = Color(0xFFF5F5F5);
  static const Color _labelDisabled = Color(0x88BDBDBD);

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(DinoCardTheme.borderRadius);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: enabled
              ? const [Color(0xFF5E5854), Color(0xFF4A4542)]
              : const [Color(0xFF464240), Color(0xFF3C3937)],
        ),
        border: Border.all(
          color: enabled
              ? const Color(0x40FFFFFF)
              : const Color(0x22FFFFFF),
          width: 0.5,
        ),
        boxShadow: enabled
            ? const [
                BoxShadow(
                  color: Color(0x44000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          splashColor: Colors.white24,
          highlightColor: Colors.white10,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: enabled ? _label : _labelDisabled,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
