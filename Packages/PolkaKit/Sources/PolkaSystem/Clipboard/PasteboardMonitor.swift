import AppKit
import PolkaCore

/// Watches the general pasteboard for new text.
///
/// macOS has no change notification for the pasteboard, so this polls
/// `changeCount` — a cheap integer read — twice a second. Content marked as
/// concealed or transient (passwords, one-time codes) is never read.
@MainActor
public final class PasteboardMonitor {
    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?
    private let onText: @MainActor (String) -> Void

    public init(pasteboard: NSPasteboard = .general, onText: @escaping @MainActor (String) -> Void) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
        self.onText = onText
    }

    public var isRunning: Bool { timer != nil }

    public func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Puts text the user picked from history back on the pasteboard without
    /// recording it again.
    public func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard ClipboardPrivacy.shouldRecord(types: types), let text = pasteboard.string(forType: .string) else { return }
        onText(text)
    }
}
