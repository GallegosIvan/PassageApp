import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var badgeChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    if let engine = engineBridge.pluginRegistry as? FlutterEngine {
      badgeChannel = FlutterMethodChannel(name: "badge_channel", binaryMessenger: engine.binaryMessenger)
      badgeChannel?.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "clearBadge" {
          UIApplication.shared.applicationIconBadgeNumber = 0
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
