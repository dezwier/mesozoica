import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/catalog_mode_controller.dart';

class CatalogModeToggle extends StatelessWidget {
  const CatalogModeToggle({super.key});

  static const _foregroundColor = Colors.white;

  @override
  Widget build(BuildContext context) {
    return Consumer<CatalogModeController>(
      builder: (context, controller, _) {
        final selected = controller.dataSource;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: SegmentedButton<CatalogDataSource>(
            segments: const [
              ButtonSegment(
                value: CatalogDataSource.archive,
                label: Text('Archive'),
              ),
              ButtonSegment(
                value: CatalogDataSource.field,
                label: Text('Field'),
              ),
            ],
            selected: {selected},
            onSelectionChanged: (selection) {
              controller.setDataSource(selection.first);
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 8),
              ),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return const Color(0xFF4A3F38);
                }
                return _foregroundColor;
              }),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return _foregroundColor;
                }
                return Colors.black.withValues(alpha: 0.35);
              }),
              side: WidgetStatePropertyAll(
                BorderSide(color: Colors.white.withValues(alpha: 0.45)),
              ),
            ),
          ),
        );
      },
    );
  }
}
