import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // The native tunnel bridge is not a pub package, so it registers here —
    // the same pattern MainActivity uses on Android.
    if let registrar = registrar(forPlugin: "VpnPlatformPlugin") {
      VpnPlatformPlugin.register(with: registrar)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
