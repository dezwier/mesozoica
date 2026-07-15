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
          color: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.7),
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
