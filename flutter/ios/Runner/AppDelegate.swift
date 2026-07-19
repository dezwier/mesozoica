import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    setupAppBadgeChannel()
    return launched
  }

  private func setupAppBadgeChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      // Window/root VC can be nil during early launch; retry on next run loop.
      DispatchQueue.main.async { [weak self] in
        self?.setupAppBadgeChannel()
      }
      return
    }
    let channel = FlutterMethodChannel(
      name: "mesozoica/app_badge",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "setBadgeCount" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let count = max(0, (call.arguments as? Int) ?? 0)
      if #available(iOS 16.0, *) {
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
          if let error = error {
            result(
              FlutterError(
                code: "badge",
                message: error.localizedDescription,
                details: nil
              )
            )
          } else {
            result(nil)
          }
        }
      } else {
        UIApplication.shared.applicationIconBadgeNumber = count
        result(nil)
      }
    }
  }
}
