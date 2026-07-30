import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../services/dinosaur_service.dart';

/// Apply a status chosen from the admin catalog dinosaur badge dropdown.
///
/// Returns the updated dinosaur summary, or null if cancelled / failed.
Future<DinosaurSummary?> applyDinosaurStatusSelection(
  BuildContext context,
  DinosaurSummary dinosaur, {
  required String newStatus,
  DinosaurService? dinosaurService,
}) async {
  final previous = dinosaur.status?.trim().toLowerCase() ?? 'hidden';
  final next = newStatus.trim().toLowerCase();
  if (next == previous) return dinosaur;

  final typeId = dinosaur.dinosaurTypeId ?? dinosaur.id;
  final service = dinosaurService ?? DinosaurService();
  final ownedService = dinosaurService == null;
  try {
    final updated = await service.setDinosaurStatus(
      dinosaurTypeId: typeId,
      status: next,
    );
    if (context.mounted) {
      _snack(context, 'Status updated to ${updated.status ?? next}.');
    }
    return updated;
  } on DinosaurServiceException catch (error) {
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
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
