import AppKit
import ImageIO
import Observation
import PolkaCore
import PolkaSystem

@MainActor
@Observable
final class ClipboardModel {
    private(set) var history = ClipboardHistory(capacity: 30)
    private(set) var lastCopiedID: ClipboardHistory.Entry.ID?

    @ObservationIgnored private var monitor: PasteboardMonitor?
    /// Small previews, made once per picture instead of on every redraw.
    @ObservationIgnored private var thumbnails: [ClipboardHistory.Entry.ID: NSImage] = [:]

    func setEnabled(_ enabled: Bool) {
        if enabled {
            if monitor == nil {
                monitor = PasteboardMonitor { [weak self] content in
                    guard let self else { return }
                    switch content {
                    case .text(let text): self.history.record(text)
                    case .image(let image): self.history.record(image)
                    }
                    self.pruneThumbnails()
                }
            }
            monitor?.start()
        } else {
            monitor?.stop()
            history.clear(keepingPinned: false)
            thumbnails = [:]
        }
    }

    func copy(_ entry: ClipboardHistory.Entry) {
        if let image = entry.image {
            monitor?.copy(image)
            history.record(image)
        } else {
            monitor?.copy(entry.text)
            history.record(entry.text)
        }
        lastCopiedID = history.entries.first?.id
        pruneThumbnails()
    }

    func thumbnail(for entry: ClipboardHistory.Entry) -> NSImage? {
        if let cached = thumbnails[entry.id] { return cached }
        guard let image = entry.image,
            let source = CGImageSourceCreateWithData(image.png as CFData, nil),
            let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 192,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary)
        else { return nil }
        let thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / 2, height: CGFloat(cgImage.height) / 2))
        thumbnails[entry.id] = thumbnail
        return thumbnail
    }

    private func pruneThumbnails() {
        let alive = Set(history.entries.map(\.id))
        thumbnails = thumbnails.filter { alive.contains($0.key) }
    }

    func togglePin(_ entry: ClipboardHistory.Entry) { history.togglePin(entry.id) }
    func remove(_ entry: ClipboardHistory.Entry) {
        history.remove(entry.id)
        pruneThumbnails()
    }

    func clear() {
        history.clear()
        pruneThumbnails()
    }
}
