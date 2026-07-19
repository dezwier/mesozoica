import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/field_discovery_coordinator.dart';
import '../../controllers/notification_controller.dart';
import '../../models/site.dart';
import '../../services/location_service.dart';
import '../../services/site_service.dart';
import '../../utils/discovery_haptic.dart';
import 'site_discovery_celebration.dart';

/// Apply a status chosen from the admin badge dropdown.
///
/// Returns the updated site, or null if cancelled / failed.
/// When transitioning hidden → discovered, shows the discovery celebration.
/// Admins may change status from any distance; lat/lon are sent when GPS is
/// available but are not required by the API.
Future<SiteSummary?> applySiteStatusSelection(
  BuildContext context,
  SiteSummary site, {
  required String newStatus,
  SiteService? siteService,
}) async {
  final previous = site.status?.trim().toLowerCase() ?? 'hidden';
  final next = newStatus.trim().toLowerCase();
  if (next == previous) return site;

  final location = context.read<LocationService>().currentLocation;
  final lat = location?.latitude;
  final lon = location?.longitude;

  final service = siteService ?? SiteService();
  final ownedService = siteService == null;
  try {
    final updated = await service.setSiteStatus(
      siteId: site.siteId,
      status: next,
      lat: lat,
      lon: lon,
    );
    if (!context.mounted) return updated;

    if (next == 'hidden') {
      context.read<FieldDiscoveryCoordinator>().siteBecameHidden(updated);
    }

    final wasHiddenToDiscover =
        previous == 'hidden' && next == 'discovered';
    if (wasHiddenToDiscover) {
      playDiscoveryHapticFireAndForget();
      final userId = context.read<AuthController>().currentUser?.id;
      if (userId != null) {
        await context.read<NotificationController>().refreshAndWait(
              authenticatedUserId: userId,
            );
      }
      if (!context.mounted) return updated;
      await showSiteDiscoveryCelebration(context, site: updated);
    } else {
      _snack(context, 'Status updated to ${updated.status ?? next}.');
    }
    return updated;
  } on SiteServiceException catch (error) {
    if (context.mounted) {
      _snack(context, error.message);
    }
    return null;
  } catch (_) {
    if (context.mounted) {
      _snack(context, 'Could not update status. Try again.');
    }
    return null;
  } finally {
    if (ownedService) {
      service.dispose();
    }
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
