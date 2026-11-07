import Foundation
import PolkaCore

/// Pages waiting for the user to pick a group, from the hotkey or the
/// Services menu.
struct SaveRequest: Identifiable, Equatable {
    enum Scope: Hashable {
        case current, window
    }

    let id = UUID()
    /// Where the pages came from, shown in the picker ("Safari", "Arc").
    var source: String
    /// The open tab, or the links the user selected.
    var current: [PageReference]
    /// Every tab of the front browser window; empty when that makes no sense.
    var window: [PageReference] = []

    var offersWindow: Bool { window.count > 1 }

    func pages(for scope: Scope) -> [PageReference] {
        scope == .window && offersWindow ? window : current
    }
}
