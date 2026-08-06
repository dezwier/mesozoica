import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../services/fossil_service.dart';
import '../common/app_toast.dart';

/// Apply a status chosen from the admin fossil badge dropdown.
///
/// Returns the updated fossil, or null if cancelled / failed.
Future<FossilSummary?> applyFossilStatusSelection(
  BuildContext context,
  FossilSummary fossil, {
  required String newStatus,
  FossilService? fossilService,
}) async {
  final previous = fossil.status?.trim().toLowerCase() ?? 'hidden';
  final next = newStatus.trim().toLowerCase();
  if (next == previous) return fossil;

  final service = fossilService ?? FossilService();
  final ownedService = fossilService == null;
  try {
    final updated = await service.setFossilStatus(
      fossilId: fossil.id,
      status: next,
    );
    if (context.mounted) {
      AppToast.success(context, 'Status updated to ${updated.status ?? next}.');
    }
    return updated;
  } on FossilServiceException catch (error) {
    if (context.mounted) {
      AppToast.error(context, error.message);
    }
    return null;
  } catch (_) {
    if (context.mounted) {
      AppToast.error(context, 'Could not update status. Try again.');
    }
    return null;
  } finally {
    if (ownedService) {
      service.dispose();
    }
  }
}
