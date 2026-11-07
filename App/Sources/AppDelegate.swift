import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var notchController: NotchWindowController?
    private var settingsController: SettingsWindowController?
    private var hotKeys: [GlobalHotKey] = []
    private var servicesProvider: ServicesProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        replaceOtherInstances()
        NSApp.mainMenu = MainMenu.make()
        let settings = SettingsWindowController(model: model)
        settingsController = settings
        model.openSettings = { [weak settings] in settings?.show() }

        let notch = NotchWindowController(model: model)
        notchController = notch
        notch.show()

        model.start()
        registerHotKeys()
        registerServices()
    }

    private func registerServices() {
        let provider = ServicesProvider { [weak self] pages, source in
            self?.model.saveFromService(pages, sourceApp: source)
        }
        servicesProvider = provider
        NSApp.servicesProvider = provider
        // Picks up the menu item without logging out after an install or update.
        NSUpdateDynamicServices()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.tabs.saveNow()
        model.media.stop()
    }

    /// Only one Polka should run: a second copy (an update, or the same app
    /// started from another folder) takes over from the first.
    private func replaceOtherInstances() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0 != NSRunningApplication.current }
        guard !others.isEmpty else { return }
        others.forEach { $0.terminate() }
        let deadline = Date.now.addingTimeInterval(3)
        while others.contains(where: { !$0.isTerminated }), Date.now < deadline {
            RunLoop.current.run(until: .now.addingTimeInterval(0.05))
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Launching Polka again from Finder or Spotlight opens its settings,
        // since there is no Dock icon to click.
        settingsController?.show()
        return false
    }

    private func registerHotKeys() {
        let modifiers = UInt32(optionKey | shiftKey)
        let toggle = GlobalHotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: modifiers) { [weak self] in
            self?.notchController?.toggleFromKeyboard()
        }
        let save = GlobalHotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: modifiers) { [weak self] in
            self?.model.saveFromBrowser()
        }
        hotKeys = [toggle, save].compactMap { $0 }
    }
}

/// Polka has no menu bar of its own, but text fields still need the standard
/// Edit commands (⌘C, ⌘V, ⌘Z…), which AppKit routes through the main menu.
@MainActor
private enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "Quit Polka"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: String(localized: "Edit"))
        edit.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        return main
    }
}
