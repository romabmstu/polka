import Observation
import PolkaCore
import PolkaSystem

@MainActor
@Observable
final class ClipboardModel {
    private(set) var history = ClipboardHistory(capacity: 30)
    private(set) var lastCopiedID: ClipboardHistory.Entry.ID?

    @ObservationIgnored private var monitor: PasteboardMonitor?

    func setEnabled(_ enabled: Bool) {
        if enabled {
            if monitor == nil {
                monitor = PasteboardMonitor { [weak self] text in self?.history.record(text) }
            }
            monitor?.start()
        } else {
            monitor?.stop()
            history.clear(keepingPinned: false)
        }
    }

    func copy(_ entry: ClipboardHistory.Entry) {
        monitor?.copy(entry.text)
        history.record(entry.text)
        lastCopiedID = history.entries.first?.id
    }

    func togglePin(_ entry: ClipboardHistory.Entry) { history.togglePin(entry.id) }
    func remove(_ entry: ClipboardHistory.Entry) { history.remove(entry.id) }
    func clear() { history.clear() }
}
