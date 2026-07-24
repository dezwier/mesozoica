import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/map_controller.dart' as map_data;
import '../../models/site.dart';
import '../../services/site_service.dart';
import '../cards/card_detail_sheet.dart';
import '../cards/site_status_helper.dart';
import '../cards/site_turnable_card.dart';
import '../common/chrome_action_button.dart';

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
                  child: ChromeActionButton(
                    label: _site.viewerHasSurveyed == true
                        ? 'Surveyed'
                        : 'Survey',
                    onPressed: _canSurvey ? _onSurvey : null,
                  ),
                ),
                const SizedBox(width: _actionGap),
                Expanded(
                  child: ChromeActionButton(
                    label: 'Protect',
                    onPressed:
                        _busy ? null : () => _onStatusAction('protected'),
                  ),
                ),
                const SizedBox(width: _actionGap),
                Expanded(
                  child: ChromeActionButton(
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
