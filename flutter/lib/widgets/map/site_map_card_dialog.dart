import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/map_controller.dart' as map_data;
import '../../models/site.dart';
import '../../services/site_service.dart';
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
      if (!result.fossilsReady && result.jobId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Surveying… fossils will appear shortly.')),
        );
        final job = await service.waitForFieldSurveyJob(result.jobId!);
        if (!mounted) return;
        if (job.isFailed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(job.errorMessage ?? 'Survey failed. Try again.'),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Survey complete.')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Site surveyed.')),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    return CardDetailSheetContent(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SiteTurnableCard(
            site: _site,
            onSiteUpdated: _onSiteUpdated,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _canSurvey ? _onSurvey : null,
                    child: Text(
                      _site.viewerHasSurveyed == true ? 'Surveyed' : 'Survey',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _busy
                        ? null
                        : () => _onStatusAction('protected'),
                    child: const Text('Protect'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _busy
                        ? null
                        : () => _onStatusAction('excavation'),
                    child: const Text('Excavate'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
