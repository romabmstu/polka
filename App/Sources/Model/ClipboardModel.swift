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
                    case .image(let image, let copiedAt): self.history.record(image, at: copiedAt)
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

    /// The small preview made in the background when the picture was copied;
    /// a picture without one is shrunk here as a fallback.
    func thumbnail(for entry: ClipboardHistory.Entry) -> NSImage? {
        if let cached = thumbnails[entry.id] { return cached }
        guard let image = entry.image, let cgImage = Self.previewImage(for: image) else { return nil }
        let thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / 2, height: CGFloat(cgImage.height) / 2))
        thumbnails[entry.id] = thumbnail
        return thumbnail
    }

    private static func previewImage(for image: ClipboardImage) -> CGImage? {
        if !image.preview.isEmpty, let source = CGImageSourceCreateWithData(image.preview as CFData, nil),
            let preview = CGImageSourceCreateImageAtIndex(source, 0, nil)
        {
            return preview
        }
        guard let source = CGImageSourceCreateWithData(image.png as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(
            source, 0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: ClipboardImageCodec.previewPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ] as CFDictionary)
    }

    private func pruneThumbnails() {
        let alive = Set(history.entries.map(\.id))
        thumbnails = thumbnails.filter { alive.contains($0.key) }
    }

    func canPin(_ entry: ClipboardHistory.Entry) -> Bool { history.canPin(entry.id) }
    func togglePin(_ entry: ClipboardHistory.Entry) { _ = history.togglePin(entry.id) }
    func remove(_ entry: ClipboardHistory.Entry) {
        history.remove(entry.id)
        pruneThumbnails()
    }

    func clear() {
        history.clear()
        pruneThumbnails()
    }
}
