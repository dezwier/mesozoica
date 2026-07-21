import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Full-screen splash shown on cold start until the initial page is ready.
/// Matches the native launch image (same placeholder asset) so the handoff
/// does not change what is on screen.
class AppSplashScreen extends StatelessWidget {
  const AppSplashScreen({super.key});

  static const AssetImage imageProvider =
      AssetImage(DinoCardTheme.frontPlaceholderAsset);

  /// Decode the splash asset while the native launch screen is still visible.
  static Future<void> prepare() async {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final dpr = dispatcher.views.isNotEmpty
        ? dispatcher.views.first.devicePixelRatio
        : dispatcher.implicitView?.devicePixelRatio ?? 1.0;
    final stream = imageProvider.resolve(ImageConfiguration(
      devicePixelRatio: dpr,
    ));
    final completer = Completer<void>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object exception, StackTrace? stackTrace) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete();
      },
    );
    stream.addListener(listener);
    await completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(
      child: Image(
        image: imageProvider,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
