import AppKit
import Observation

/// Where the panel lives on screen and whether it is open.
@MainActor
@Observable
final class PanelState {
    enum Style: Equatable {
        /// Grows out of the camera housing on MacBooks.
        case notch(width: CGFloat, height: CGFloat)
        /// A compact control inside the menu bar on displays without a notch.
        case pill(menuBarHeight: CGFloat)
    }

    struct Flash: Equatable, Identifiable {
        let id = UUID()
        var symbol: String
        var text: String
        var canUndo = false
    }

    static let expandedSize = CGSize(width: 760, height: 420)
    /// The capsule sits inside the menu bar with this much air above and below.
    static let pillInset: CGFloat = 3.5
    /// Hover target for the capsule, wider than the capsule itself.
    static let pillHitWidth: CGFloat = 150
    /// Gap between the menu bar and the open panel on displays without a notch.
    static let pillPanelGap: CGFloat = 6

    static func pillHeight(menuBar: CGFloat) -> CGFloat {
        max(16, menuBar - 2 * pillInset)
    }

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
