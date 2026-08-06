import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/aerial_session_controller.dart';
import '../../controllers/dinosaur_catalog_controller.dart';
import '../../controllers/field_discovery_coordinator.dart';
import '../../controllers/fossil_catalog_controller.dart';
import '../../controllers/site_catalog_controller.dart';
import '../../controllers/tool_catalog_controller.dart';
import '../../models/dinosaur.dart';
import '../../models/fossil.dart';
import '../../models/site.dart';
import '../../models/tool.dart';
import '../../services/dinosaur_service.dart';
import '../../services/fossil_service.dart';
import '../../services/site_service.dart';
import '../../services/tool_service.dart';
import '../common/app_toast.dart';
import 'card_settings_drawer.dart';

Future<void> openInventoryCardSettings({
  required BuildContext context,
  required Future<void> Function() onThrowAway,
}) {
  return showCardSettingsDrawer(context, onThrowAway: onThrowAway);
}

Future<void> discardDinosaurFromInventory(
  BuildContext context,
  DinosaurSummary dinosaur,
) async {
  final service = DinosaurService();
  try {
    await service.discardDinosaur(dinosaur.id);
    if (!context.mounted) return;
    context.read<DinosaurCatalogController>().removeDinosaur(dinosaur.id);
  } catch (e) {
    if (!context.mounted) return;
    AppToast.show(
      context,
      e is DinosaurServiceException ? e.message : 'Failed to throw card away',
      tone: AppToastTone.error,
    );
  } finally {
    service.dispose();
  }
}

Future<void> discardToolFromInventory(
  BuildContext context,
  ToolSummary tool,
) async {
  final service = ToolService();
  try {
    await service.discardTool(tool.id);
    if (!context.mounted) return;
    context.read<ToolCatalogController>().removeTool(tool.id);
    // Best-effort: drop any local HUD session for the discarded card.
    try {
      await context.read<AerialSessionController>().refreshSessions();
    } catch (_) {}
  } catch (e) {
    if (!context.mounted) return;
    AppToast.show(
      context,
      e is ToolServiceException ? e.message : 'Failed to throw card away',
      tone: AppToastTone.error,
    );
  } finally {
    service.dispose();
  }
}

Future<void> discardSiteFromInventory(
  BuildContext context,
  SiteSummary site,
) async {
  final service = SiteService();
  try {
    await service.discardSite(site.siteId);
    if (!context.mounted) return;
    context.read<SiteCatalogController>().removeSite(site.siteId);
    context.read<FieldDiscoveryCoordinator>().siteBecameHidden(
      site.copyWith(status: 'hidden'),
    );
  } catch (e) {
    if (!context.mounted) return;
    AppToast.show(
      context,
      e is SiteServiceException ? e.message : 'Failed to throw card away',
      tone: AppToastTone.error,
    );
  } finally {
    service.dispose();
  }
}

Future<void> discardFossilFromInventory(
  BuildContext context,
  FossilSummary fossil,
) async {
  final service = FossilService();
  try {
    await service.discardFossil(fossil.id);
    if (!context.mounted) return;
    context.read<FossilCatalogController>().removeFossil(fossil.id);
  } catch (e) {
    if (!context.mounted) return;
    AppToast.show(
      context,
      e is FossilServiceException ? e.message : 'Failed to throw card away',
      tone: AppToastTone.error,
    );
  } finally {
    service.dispose();
  }
}
