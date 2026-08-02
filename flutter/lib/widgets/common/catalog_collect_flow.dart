import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../models/tool.dart';
import '../../services/dinosaur_service.dart';
import '../../services/tool_service.dart';
import 'app_toast.dart';

/// Shared admin collect dialogs / API calls for catalog album tiles.
class CatalogCollectFlow {
  CatalogCollectFlow._();

  static Future<String?> pickDinosaurStatus(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Choose status'),
          children: [
            for (final option in const [
              ('modelled', 'Modelled'),
              ('reconstructed', 'Reconstructed'),
            ])
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(option.$1),
                child: Text(option.$2),
              ),
          ],
        );
      },
    );
  }

  static Future<String?> pickImageVersion(
    BuildContext context,
    List<String> versions,
  ) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Choose image version'),
          children: [
            for (final name in versions)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(name),
                child: Text(name),
              ),
          ],
        );
      },
    );
  }

  /// Status + version dialogs, then POST collect. Returns the new occurrence.
  static Future<DinosaurSummary?> collectDinosaur(
    BuildContext context, {
    required int dinosaurTypeId,
  }) async {
    final status = await pickDinosaurStatus(context);
    if (!context.mounted || status == null) return null;

    final service = DinosaurService();
    try {
      final versions = await service.listDinosaurImageVersions();
      if (!context.mounted) return null;
      if (versions.isEmpty) {
        AppToast.warning(context, 'No image versions available');
        return null;
      }
      final version = await pickImageVersion(context, versions);
      if (!context.mounted || version == null) return null;

      final created = await service.collectDinosaur(
        dinosaurTypeId: dinosaurTypeId,
        status: status,
        version: version,
      );
      if (!context.mounted) return created;
      AppToast.success(context, 'Added to your collection');
      return created;
    } on DinosaurServiceException catch (error) {
      if (context.mounted) {
        AppToast.error(context, error.message);
      }
      return null;
    } catch (_) {
      if (context.mounted) {
        AppToast.error(context, 'Failed to add dinosaur');
      }
      return null;
    } finally {
      service.dispose();
    }
  }

  /// Version dialog, then POST collect. Returns the new occurrence.
  static Future<ToolSummary?> collectTool(
    BuildContext context, {
    required int toolTypeId,
  }) async {
    final service = ToolService();
    try {
      final versions = await service.listToolImageVersions();
      if (!context.mounted) return null;
      if (versions.isEmpty) {
        AppToast.warning(context, 'No image versions available');
        return null;
      }
      final version = await pickImageVersion(context, versions);
      if (!context.mounted || version == null) return null;

      final created = await service.collectTool(
        toolTypeId,
        version: version,
      );
      if (!context.mounted) return created;
      AppToast.success(context, 'Added to your collection');
      return created;
    } on ToolServiceException catch (error) {
      if (context.mounted) {
        AppToast.error(context, error.message);
      }
      return null;
    } catch (_) {
      if (context.mounted) {
        AppToast.error(context, 'Failed to add tool');
      }
      return null;
    } finally {
      service.dispose();
    }
  }
}
