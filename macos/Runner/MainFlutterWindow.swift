import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Enforce a phone-like minimum so the mobile-first UI stays usable.
    self.minSize = NSSize(width: 360, height: 780)

    let autosaveName = "CupolaMainWindow"
    let isFirstLaunch =
      UserDefaults.standard.object(forKey: "NSWindow Frame \(autosaveName)") == nil

    if isFirstLaunch {
      // First launch: default to an iPhone 15 portrait content size, centered.
      self.setContentSize(NSSize(width: 393, height: 852))
      if let screen = NSScreen.main {
        let visible = screen.visibleFrame
        let frame = self.frame
        self.setFrameOrigin(NSPoint(
          x: visible.midX - frame.width / 2,
          y: visible.midY - frame.height / 2,
        ))
      }
    }
    // Register autosave on every launch: first launch saves the new default,
    // subsequent launches restore the user's last frame (size + position).
    _ = self.setFrameAutosaveName(autosaveName)

    RegisterGeneratedPlugins(registry: flutterViewController)

    SecureClipboardChannel.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

/// Copies a credential without letting it reach the user's other devices.
///
/// The general pasteboard syncs through Universal Clipboard, so a plain copy of
/// an API key hands it to every Mac, iPhone and iPad signed into the same
/// account. `NSPasteboard.ContentsOptions.currentHostOnly` is what keeps a clip
/// on this machine, and it is not reachable from Flutter's clipboard plumbing —
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

      result(copySecret(secret))
    }
  }

  private static func copySecret(_ secret: String) -> Bool {
    // No availability guard: `prepareForNewContents(with:)` and
    // `.currentHostOnly` are both macOS 10.12 API and this app deploys to
    // 10.15, so every version that can run it can harden the clip. A
    // `#available(macOS 11.0, *)` guard used to sit here and returned false on
    // 10.15/10.16, which sent `_copyApiKey` down its plain-copy fallback and
    // put the API key on the syncing general pasteboard — the exact leak this
    // channel exists to close, disabled on the oldest OS it supports.
    let pasteboard = NSPasteboard.general
    // Replaces clearContents(): it clears and applies the options to whatever is
    // written next. AppKit has no pasteboard expiry, so the Dart-side timed
    // clear stays the mitigation for how long the key lingers.
    pasteboard.prepareForNewContents(with: .currentHostOnly)
    return pasteboard.setString(secret, forType: .string)
  }
}
