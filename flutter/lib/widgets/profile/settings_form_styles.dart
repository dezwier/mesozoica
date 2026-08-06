import 'package:flutter/material.dart';

/// Shared form styling for settings drawer tabs (Archipelago layout).
class SettingsFormStyles {
  SettingsFormStyles._();

  static InputDecoration createStyleDecoration(
    BuildContext context, {
    required String labelText,
    Widget? suffixIcon,
    String? errorText,
    String? counterText,
  }) {
    final outlineColor = Theme.of(context).brightness == Brightness.light
        ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)
        : Theme.of(context).colorScheme.outline.withValues(alpha: 0.5);

    return InputDecoration(
      labelText: labelText,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      suffixIcon: suffixIcon,
      errorText: errorText,
      counterText: counterText,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: outlineColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: outlineColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
    );
  }

  static OutlineInputBorder outlineBorder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: scheme.outline.withValues(alpha: isLight ? 0.3 : 0.5),
      ),
    );
  }

  static TextStyle? finePrintStyle(BuildContext context) {
    return Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
    );
  }

  static Widget settingsRow({
    required BuildContext context,
    required String label,
    required String description,
    required Widget control,
    double controlWidth = 160,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(description, style: finePrintStyle(context)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(width: controlWidth, child: control),
      ],
    );
  }

  static Widget densePopupField<T>({
    required BuildContext context,
    required InputBorder outlineBorder,
    required Widget selectedChild,
    required List<DensePopupEntry<T>> entries,
    required ValueChanged<T?> onSelected,
    bool enabled = true,
  }) {
    return DecoratedBox(
      decoration: ShapeDecoration(shape: outlineBorder),
      child: SizedBox(
        height: 48,
        child: PopupMenuButton<T?>(
          enabled: enabled,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 220),
          offset: const Offset(0, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onSelected: onSelected,
          itemBuilder: (context) => entries
              .map(
                (entry) => PopupMenuItem<T?>(
                  value: entry.value,
                  enabled: entry.enabled,
                  height: entry.height,
                  child: entry.child,
                ),
              )
              .toList(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(child: selectedChild),
                Icon(
                  Icons.arrow_drop_down,
                  color: enabled
                      ? IconTheme.of(context).color
                      : Theme.of(context).disabledColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Multi-select companion to [densePopupField] — same chrome, checkboxes
  /// inside a [MenuAnchor] so the menu stays open while toggling.
  static Widget multiSelectDensePopup({
    required BuildContext context,
    required InputBorder outlineBorder,
    required Widget selectedChild,
    required List<MultiSelectPopupEntry> entries,
    required void Function(String value, bool selected) onToggle,
    void Function(String value)? onSelectOnly,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(shape: outlineBorder),
      child: SizedBox(
        height: 48,
        child: MenuAnchor(
          alignmentOffset: const Offset(0, 4),
          style: MenuStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            maximumSize: const WidgetStatePropertyAll(Size(320, 360)),
          ),
          builder: (context, controller, _) {
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: !enabled
                  ? null
                  : () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: selectedChild),
                    Icon(
                      Icons.arrow_drop_down,
                      color: enabled
                          ? IconTheme.of(context).color
                          : Theme.of(context).disabledColor,
                    ),
                  ],
                ),
              ),
            );
          },
          menuChildren: [
            for (final entry in entries)
              _MultiSelectMenuRow(
                label: entry.label,
                selected: entry.selected,
                enabled: enabled && entry.enabled,
                labelStyle: theme.textTheme.bodyMedium,
                onToggle: () => onToggle(entry.value, !entry.selected),
                onSelectOnly: onSelectOnly == null
                    ? null
                    : () => onSelectOnly(entry.value),
              ),
          ],
        ),
      ),
    );
  }

  /// Summary label for a multi-select set (All / None / "3 of 12").
  static String multiSelectSummary({
    required int selectedCount,
    required int totalCount,
  }) {
    if (selectedCount <= 0) return 'None';
    if (selectedCount >= totalCount) return 'All';
    return '$selectedCount of $totalCount';
  }
}

class _MultiSelectMenuRow extends StatelessWidget {
  const _MultiSelectMenuRow({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.labelStyle,
    required this.onToggle,
    this.onSelectOnly,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final TextStyle? labelStyle;
  final VoidCallback onToggle;
  final VoidCallback? onSelectOnly;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: InkWell(
        onTap: enabled ? onToggle : null,
        onLongPress: !enabled || onSelectOnly == null
            ? null
            : () {
                Feedback.forLongPress(context);
                onSelectOnly!();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                height: 40,
                child: IgnorePointer(
                  child: Checkbox(
                    value: selected,
                    onChanged: enabled ? (_) {} : null,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(
                      horizontal: -4,
                      vertical: -4,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(child: Text(label, style: labelStyle)),
            ],
          ),
        ),
      ),
    );
  }
}

class DensePopupEntry<T> {
  const DensePopupEntry({
    this.value,
    required this.child,
    this.enabled = true,
    this.height = 44,
  });

  final T? value;
  final Widget child;
  final bool enabled;
  final double height;
}

class MultiSelectPopupEntry {
  const MultiSelectPopupEntry({
    required this.value,
    required this.label,
    required this.selected,
    this.enabled = true,
  });

  final String value;
  final String label;
  final bool selected;
  final bool enabled;
}
