import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let controller = window?.rootViewController as? FlutterViewController {
      let badgeChannel = FlutterMethodChannel(
        name: "badge_channel",
        binaryMessenger: controller.binaryMessenger
      )
      badgeChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "clearBadge" {
          UIApplication.shared.applicationIconBadgeNumber = 0
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
