import AppKit
import ApplicationServices

/// Sends the same events as the play/pause and track keys on a Mac keyboard,
/// so it controls whatever app currently owns "Now Playing" — Yandex Music,
/// Music, Spotify, a video in Safari.
///
/// Posting system events needs the Accessibility permission.
@MainActor
public enum MediaKeys {
    public enum Key: Int {
        case playPause = 16
        case next = 17
        case previous = 18
    }

    public static var isAllowed: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security.
    public static func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    public static func press(_ key: Key) -> Bool {
        guard isAllowed else { return false }
        post(key, down: true)
        post(key, down: false)
        return true
    }

    private static func post(_ key: Key, down: Bool) {
        // NX_SYSDEFINED / NX_SUBTYPE_AUX_CONTROL_BUTTONS, see IOKit/hidsystem/ev_keymap.h
        let state = down ? 0xA : 0xB
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: (key.rawValue << 16) | (state << 8),
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }
}
