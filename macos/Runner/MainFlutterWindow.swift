import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Enforce a phone-like minimum so the mobile-first UI stays usable.
    self.minSize = NSSize(width: 360, height: 780)

    let autosaveName = "SeekarrMainWindow"
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

    super.awakeFromNib()
  }
}
