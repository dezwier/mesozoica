import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-screen splash shown on cold start until the initial page is ready.
///
/// Images live only in [splashAssets] (`assets/images/splash/`). Native iOS
/// and Android load the same files from the Flutter asset bundle. Native picks
/// the dinosaur for this launch; Flutter reuses that index so the handoff
/// does not flash a different image.
class AppSplashScreen extends StatelessWidget {
  const AppSplashScreen({super.key});

  static const MethodChannel _channel = MethodChannel('mesozoica/splash');

  static const List<String> splashAssets = [
    'assets/images/splash/giganotosaurus.png',
    'assets/images/splash/tyrannosaurus.png',
    'assets/images/splash/triceratops.png',
    'assets/images/splash/spinosaurus.png',
    'assets/images/splash/microraptor.png',
    'assets/images/splash/argentinosaurus.png',
  ];

  static late final AssetImage imageProvider;

  /// Resolve the launch-picked splash asset and decode it before [runApp].
  static Future<void> prepare() async {
    final index = await _resolveSplashIndex();
    imageProvider = AssetImage(splashAssets[index]);

    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final dpr = dispatcher.views.isNotEmpty
        ? dispatcher.views.first.devicePixelRatio
        : dispatcher.implicitView?.devicePixelRatio ?? 1.0;
    final stream = imageProvider.resolve(
      ImageConfiguration(devicePixelRatio: dpr),
    );
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

  static Future<int> _resolveSplashIndex() async {
    // Native registers the channel during engine startup; retry briefly so we
    // reuse the same index the native splash is already showing.
    for (var attempt = 0; attempt < 40; attempt++) {
      try {
        final value = await _channel.invokeMethod<int>('getSplashIndex');
        if (value != null && value >= 0 && value < splashAssets.length) {
          return value;
        }
        break;
      } on MissingPluginException {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      } on PlatformException {
        break;
      }
    }
    return Random().nextInt(splashAssets.length);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
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
