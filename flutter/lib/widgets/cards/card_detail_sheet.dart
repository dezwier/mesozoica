import 'package:flutter/material.dart';

/// Shared presentation for card detail bottom sheets (map taps, cross-links).
class CardDetailSheet {
  CardDetailSheet._();

  /// Clears the app [NavigationBar] plus a small gap.
  static const double navigationBarClearance = 52;

  static const double bottomGap = 16;

  static double bottomOffset(BuildContext context) {
    return navigationBarClearance +
        bottomGap +
        MediaQuery.paddingOf(context).bottom;
  }

  static double maxContentHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    return size.height - bottomOffset(context) - padding.top - 8;
  }

  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CardDetailSheetShell(child: builder(context)),
    );
  }
}

class CardDetailSheetShell extends StatelessWidget {
  const CardDetailSheetShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: CardDetailSheet.bottomOffset(context)),
      child: Material(
        color: Colors.transparent,
        child: child,
      ),
    );
  }
}

/// Scrollable card body sized to content, capped by [CardDetailSheet.maxContentHeight].
class CardDetailSheetContent extends StatelessWidget {
  const CardDetailSheetContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: CardDetailSheet.maxContentHeight(context),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        children: [child],
      ),
    );
  }
}
