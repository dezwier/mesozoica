import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/field_discovery_coordinator.dart';
import '../../controllers/notification_controller.dart';
import '../../models/site.dart';
import '../../services/location_service.dart';
import '../../services/site_service.dart';
import '../../utils/discovery_haptic.dart';
import 'site_discovery_celebration.dart';

const setStatusMaxDistanceMeters = 500.0;

/// Apply a status chosen from the badge dropdown.
///
/// Returns the updated site, or null if cancelled / failed.
/// When transitioning hidden → discovered, shows the discovery celebration.
Future<SiteSummary?> applySiteStatusSelection(
  BuildContext context,
  SiteSummary site, {
  required String newStatus,
  SiteService? siteService,
}) async {
  final previous = site.status?.trim().toLowerCase() ?? 'hidden';
  final next = newStatus.trim().toLowerCase();
  if (next == previous) return site;

  final needsLocation = next != 'hidden';
  double? lat;
  double? lon;
  if (needsLocation) {
    final siteLat = site.latitude;
    final siteLon = site.longitude;
    if (siteLat == null || siteLon == null) {
      _snack(context, 'This site has no coordinates.');
      return null;
    }
    final location = context.read<LocationService>().currentLocation;
    if (location == null) {
      _snack(context, 'Location unavailable. Enable GPS and try again.');
      return null;
    }
    final distanceM = Geolocator.distanceBetween(
      location.latitude,
      location.longitude,
      siteLat,
      siteLon,
    );
    if (distanceM > setStatusMaxDistanceMeters) {
      _snack(
        context,
        'Too far away (${distanceM.round()} m). '
        'Get within ${setStatusMaxDistanceMeters.round()} m to change status.',
      );
      return null;
    }
    lat = location.latitude;
    lon = location.longitude;
  }

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
