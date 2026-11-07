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
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("PolkaSettings")
            self.window = window
        }
        model.panel.collapse()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
