import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Blend the title bar into the app: transparent, no title text, and the
    // Flutter content extends under it. The app adds a top inset so nothing
    // sits beneath the traffic-light buttons (see AppChrome.macTitleBarInset).
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = false
    // DESIGN.md §2: resizable window, min ~900 × 640.
    self.minSize = NSSize(width: 900, height: 640)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
