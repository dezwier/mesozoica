import Flutter
import UIKit
import MapboxMaps

/// Mapbox FollowPuck drops to Idle on any touch unless this flag is false.
/// The Flutter SDK does not expose ViewportOptions, so we set it on MapView(s)
/// found in the hierarchy after the platform view mounts.
enum MapboxViewportFix {
  static let channelName = "mesozoica/mapbox_viewport"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "disableViewportIdleOnInteraction" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(applyToKeyWindow())
    }
  }

  @discardableResult
  static func applyToKeyWindow() -> Int {
    let roots: [UIView] = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .compactMap(\.rootViewController?.view)
    var count = 0
    for root in roots {
      count += apply(to: root)
    }
    return count
  }

  @discardableResult
  static func apply(to root: UIView) -> Int {
    var count = 0
    if let mapView = root as? MapView {
      var options = mapView.viewport.options
      if options.transitionsToIdleUponUserInteraction {
        options.transitionsToIdleUponUserInteraction = false
        mapView.viewport.options = options
      }
      count += 1
    }
    for subview in root.subviews {
      count += apply(to: subview)
    }
    return count
  }
}
