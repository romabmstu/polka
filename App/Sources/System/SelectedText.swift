import ApplicationServices
import PolkaCore

/// Reads the text selected in the frontmost app through the Accessibility API,
/// for ⌥⇧T. Needs the Accessibility permission; without it Polka falls back to
/// an empty translator and the Services menu.
@MainActor
enum SelectedText {
    static var isAllowed: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to Privacy & Security › Accessibility.
    static func requestAccess() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func read() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success,
            let text = selected as? String
        else { return nil }
        return TranslationRoute.prepare(text)
    }
}
