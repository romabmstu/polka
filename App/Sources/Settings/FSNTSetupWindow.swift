import AppKit
import SwiftUI

/// Opens the same setup screen from the VPN tile as from Settings.
@MainActor
enum FSNTSetupWindow {
    private static var window: NSWindow?

    static func show(_ app: AppModel) {
        if window == nil {
            let controller = NSHostingController(rootView: ThroneSettings().environment(app))
            let newWindow = NSWindow(contentViewController: controller)
            newWindow.title = String(localized: "Set up FSNT / Throne")
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.setContentSize(NSSize(width: 560, height: 500))
            newWindow.minSize = NSSize(width: 420, height: 380)
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        app.panel.collapse()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
