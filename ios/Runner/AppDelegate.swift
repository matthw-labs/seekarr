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
    // Lets a notification tapped while the app is running reach Dart. Deliberately
    // the only iOS-side change: a background URLSession needs no UIBackgroundModes
    // and no entitlement, so there is nothing here to justify at App Store review.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    if let controller = window?.rootViewController as? FlutterViewController {
      SecureClipboardChannel.register(with: controller.binaryMessenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

/// Copies a credential without letting it reach the user's other devices.
///
/// The general pasteboard syncs through Universal Clipboard, so a plain copy of
/// an API key hands it to every other device signed into the same account.
/// `localOnly` is what keeps it on this one and `expirationDate` is what stops
/// it lingering there; neither is reachable from Flutter's clipboard plumbing —
/// hence this channel. Dart falls back to a plain copy whenever `copySecret`
/// answers false, so nothing here can break the copy button.
enum SecureClipboardChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.matthwlabs.cupola/secure_clipboard",
      binaryMessenger: messenger
    )

    channel.setMethodCallHandler { call, result in
      guard call.method == "copySecret" else {
        result(FlutterMethodNotImplemented)
        return
      }

      let arguments = call.arguments as? [String: Any]
      guard let secret = arguments?["secret"] as? String, !secret.isEmpty else {
        result(false)
        return
      }

      let seconds = arguments?["expiresInSeconds"] as? Int ?? 0
      result(copySecret(secret, expiresIn: seconds))
    }
  }

  private static func copySecret(_ secret: String, expiresIn seconds: Int) -> Bool {
    // Spelled out rather than taken from UniformTypeIdentifiers: the string is
    // the pasteboard's own identifier and importing a framework for it would be
    // the only new dependency in this file.
    let plainText = "public.utf8-plain-text"
    var options: [UIPasteboard.OptionsKey: Any] = [.localOnly: true]
    if seconds > 0 {
      // UIKit expires the item itself, so the key is gone even if the app never
      // gets to run its own timed clear. That clear stays as well: it is the
      // only half of this that works on every OS.
      options[.expirationDate] = Date().addingTimeInterval(TimeInterval(seconds))
    }

    UIPasteboard.general.setItems([[plainText: secret]], options: options)
    return true
  }
}
