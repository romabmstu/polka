import AppKit
import Observation

/// Where the panel lives on screen and whether it is open.
@MainActor
@Observable
final class PanelState {
    enum Style: Equatable {
        /// Grows out of the camera housing on MacBooks.
        case notch(width: CGFloat, height: CGFloat)
        /// A floating capsule under the menu bar on displays without a notch.
        case pill(menuBarHeight: CGFloat)
    }

    struct Flash: Equatable, Identifiable {
        let id = UUID()
        var symbol: String
        var text: String
        var canUndo = false
    }

    static let expandedSize = CGSize(width: 760, height: 420)
    static let pillSize = CGSize(width: 220, height: 36)
    static let pillGap: CGFloat = 6

    private(set) var isExpanded = false
    private(set) var isPinned = false
    var section: PanelSection = .overview
    var style: Style = .pill(menuBarHeight: 24)
    private(set) var flash: Flash?
    /// Set while a text field in the panel is being edited, so the panel does
    /// not close under the user's fingers.
    var isEditingText = false
    /// Pages waiting for a destination; while set, the panel shows the picker.
    private(set) var saveRequest: SaveRequest?

    @ObservationIgnored var onExpand: () -> Void = {}
    @ObservationIgnored var onCollapse: () -> Void = {}
    /// Opens the panel on the right display and gives it the keyboard.
    @ObservationIgnored var openForKeyboard: () -> Void = {}
    @ObservationIgnored private var flashTask: Task<Void, Never>?

    var hasNotch: Bool {
        if case .notch = style { return true }
        return false
    }

    /// Height of the camera housing, or 0 without a notch. Expanded content
    /// starts below it.
    var notchHeight: CGFloat {
        if case .notch(_, let height) = style { return height }
        return 0
    }

    func expand(pinned: Bool = false) {
        if pinned { isPinned = true }
        guard !isExpanded else { return }
        isExpanded = true
        onExpand()
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        isPinned = false
        isEditingText = false
        saveRequest = nil
        onCollapse()
    }

    func presentSavePicker(_ request: SaveRequest) {
        saveRequest = request
        openForKeyboard()
    }

    func dismissSavePicker() {
        saveRequest = nil
    }

    func togglePin() {
        isPinned.toggle()
        if isPinned { expand() }
    }

    func flash(_ value: Flash, duration: Duration = .seconds(2.4)) {
        flash = value
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.flash = nil
        }
    }

    func dismissFlash() {
        flashTask?.cancel()
        flash = nil
    }
}
