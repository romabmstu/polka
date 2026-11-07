import Foundation

/// A named set of actions run together, e.g. "Work": connect VPN, open the
/// work tabs, start music.
public struct Scenario: Identifiable, Hashable, Codable, Sendable {
    public enum Action: Hashable, Codable, Sendable {
        /// `nil` disconnects every VPN.
        case vpn(serviceID: String?)
        case media(MediaCommand)
        case openTabGroup(UUID)
        /// Runs a shortcut from the Shortcuts app — the supported way to switch
        /// Focus modes and do anything else the system does not expose directly.
        case runShortcut(name: String)
        case openURL(URL)
    }

    public enum MediaCommand: String, Codable, Sendable, CaseIterable {
        case play, pause
    }

    public var id: UUID
    public var name: String
    public var symbol: String
    public var actions: [Action]

    public init(id: UUID = UUID(), name: String, symbol: String, actions: [Action]) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.actions = actions
    }

    /// Shortcut names end up as a process argument; keep them to something a
    /// person would actually type in the Shortcuts app.
    public static func isValidShortcutName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.count <= 200 && !trimmed.contains(where: \.isNewline)
            && !trimmed.hasPrefix("-")
    }
}
