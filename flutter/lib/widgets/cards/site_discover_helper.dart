import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../models/site.dart';
import '../../services/location_service.dart';
import '../../services/site_service.dart';

const discoverMaxDistanceMeters = 20.0;

/// Confirm + proximity-gated discover for a hidden field site.
Future<SiteSummary?> promptDiscoverSite(
  BuildContext context,
  SiteSummary site, {
  SiteService? siteService,
}) async {
  final status = site.status?.trim().toLowerCase();
  if (status != 'hidden') return null;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Discover site?'),
      content: const Text(
        'Mark yourself as a discoverer of this site? '
        'You must be within 20 meters.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Discover'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return null;

  final lat = site.latitude;
  final lon = site.longitude;
  if (lat == null || lon == null) {
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
    lat,
    lon,
  );
  if (distanceM > discoverMaxDistanceMeters) {
    _snack(
      context,
      'Too far away (${distanceM.round()} m). '
      'Get within ${discoverMaxDistanceMeters.round()} m to discover.',
    );
    return null;
  }

  final service = siteService ?? SiteService();
  final ownedService = siteService == null;
  try {
    final updated = await service.discoverSite(
      siteId: site.siteId,
      lat: location.latitude,
      lon: location.longitude,
    );
    if (context.mounted) {
      _snack(context, 'Site discovered!');
    }
    return updated;
  } on SiteServiceException catch (error) {
    if (context.mounted) {
      _snack(context, error.message);
    }
    return null;
  } catch (_) {
    if (context.mounted) {
      _snack(context, 'Could not discover site. Try again.');
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
