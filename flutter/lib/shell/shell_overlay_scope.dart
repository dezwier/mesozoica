import 'package:flutter/material.dart';

/// Provides [onClose] / [opaque] to overlay children (e.g. catalog bottom bars).
class ShellOverlayScope extends InheritedWidget {
  const ShellOverlayScope({
    super.key,
    required this.onClose,
    required this.opaque,
    required super.child,
  });

  final VoidCallback onClose;
  final bool opaque;

  static ShellOverlayScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellOverlayScope>();

  static ShellOverlayScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'ShellOverlayScope not found');
    return scope!;
  }

  @override
  bool updateShouldNotify(ShellOverlayScope oldWidget) =>
      onClose != oldWidget.onClose || opaque != oldWidget.opaque;
}
