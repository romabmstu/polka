import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView().environment(model))
            let window = NSWindow(contentViewController: controller)
            window.title = String(localized: "Polka Settings")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 760, height: 620))
            window.minSize = NSSize(width: 720, height: 560)
            window.center()
            window.setFrameAutosaveName("PolkaSettings")
            self.window = window
        }
        model.panel.collapse()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
