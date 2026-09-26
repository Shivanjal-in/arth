import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Local notifications (review reminders) show while the app is open and
    // report taps; FlutterAppDelegate passes these on to the plugins.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // A device id that survives reinstalling the app (the free AI allowance
    // is per phone): kept in the Keychain, which outlives the app.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ArthDevice") {
      let channel = FlutterMethodChannel(name: "arth/device", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        if call.method == "stableId" {
          result(StableDeviceId.value())
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}

/// A random id created once and kept in the Keychain. "This device only":
/// it isn't synced to the reader's other devices or restored onto a new one.
enum StableDeviceId {
  private static let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.zethyst.arth.device",
    kSecAttrAccount as String: "id",
  ]

  static func value() -> String? {
    var read = query
    read[kSecReturnData as String] = true
    read[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    if SecItemCopyMatching(read as CFDictionary, &item) == errSecSuccess,
       let data = item as? Data, let id = String(data: data, encoding: .utf8) {
      return id
    }
    let id = UUID().uuidString
    var add = query
    add[kSecValueData as String] = Data(id.utf8)
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(add as CFDictionary, nil) == errSecSuccess ? id : nil
  }
}
