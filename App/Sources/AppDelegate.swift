import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var notchController: NotchWindowController?
    private var settingsController: SettingsWindowController?
    private var hotKeys: [GlobalHotKey] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        let settings = SettingsWindowController(model: model)
        settingsController = settings
        model.openSettings = { [weak settings] in settings?.show() }

        let notch = NotchWindowController(model: model)
        notchController = notch
        notch.show()

        model.start()
        registerHotKeys()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.tabs.saveNow()
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
            self?.model.saveCurrentSafariTab()
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
