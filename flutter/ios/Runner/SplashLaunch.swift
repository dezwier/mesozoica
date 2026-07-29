import Flutter
import UIKit

/// Picks one splash dinosaur per cold start and keeps native + Flutter in sync.
///
/// Images live only in `assets/images/splash/` (Flutter assets); native loads
/// them from the Flutter asset bundle — do not duplicate into xcassets.
enum SplashLaunch {
  static let channelName = "mesozoica/splash"
  static let names = [
    "giganotosaurus",
    "tyrannosaurus",
    "triceratops",
    "spinosaurus",
    "microraptor",
    "argentinosaurus",
  ]

  private static let indexKey = "mesozoica_splash_index"
  private static let assetPrefix = "assets/images/splash/"

  /// Chosen once per process; Flutter reads this via the method channel.
  private(set) static var index: Int = {
    let value = Int.random(in: 0..<names.count)
    UserDefaults.standard.set(value, forKey: indexKey)
    return value
  }()

  static var assetName: String { names[index] }

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getSplashIndex":
        result(index)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Replace Flutter's default launch-storyboard splash with the chosen dino
  /// so it matches the Flutter [AppSplashScreen] that follows.
  static func installSplash(on controller: FlutterViewController) {
    let imageView = UIImageView(image: imageFromFlutterAssets(named: assetName))
    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    imageView.backgroundColor = UIColor(
      red: 0.1647058824,
      green: 0.1215686275,
      blue: 0.07843137255,
      alpha: 1
    )
    controller.splashScreenView = imageView
    controller.view.backgroundColor = imageView.backgroundColor
  }

  private static func imageFromFlutterAssets(named name: String) -> UIImage? {
    let assetPath = "\(assetPrefix)\(name).png"
    let key = FlutterDartProject.lookupKey(forAsset: assetPath)
    let bundles = [
      Bundle(identifier: "io.flutter.flutter.app"),
      Bundle.main,
    ].compactMap { $0 }

    for bundle in bundles {
      if let image = image(forLookupKey: key, in: bundle) {
        return image
      }
    }
    return nil
  }

  private static func image(forLookupKey key: String, in bundle: Bundle) -> UIImage? {
    let nsKey = key as NSString
    if let path = bundle.path(
      forResource: nsKey.lastPathComponent,
      ofType: nil,
      inDirectory: nsKey.deletingLastPathComponent
    ), let image = UIImage(contentsOfFile: path) {
      return image
    }
    let url = bundle.bundleURL.appendingPathComponent(key)
    if FileManager.default.fileExists(atPath: url.path) {
      return UIImage(contentsOfFile: url.path)
    }
    return nil
  }
}
