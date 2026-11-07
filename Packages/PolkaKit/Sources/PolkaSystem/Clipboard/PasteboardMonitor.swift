import AppKit
import PolkaCore

/// Watches the general pasteboard for new text and pictures.
///
/// macOS has no change notification for the pasteboard, so this polls
/// `changeCount` — a cheap integer read — twice a second. Content marked as
/// concealed or transient (passwords, one-time codes) is never read.
@MainActor
public final class PasteboardMonitor {
    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?
    public enum Content {
        case text(String)
        case image(ClipboardImage)
    }

    private let onContent: @MainActor (Content) -> Void

    public init(pasteboard: NSPasteboard = .general, onContent: @escaping @MainActor (Content) -> Void) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
        self.onContent = onContent
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

    /// Puts a picture from history back on the pasteboard, as PNG and TIFF so
    /// older apps can paste it too.
    public func copy(_ image: ClipboardImage) {
        pasteboard.clearContents()
        if let picture = NSImage(data: image.png) {
            pasteboard.writeObjects([picture])
        }
        pasteboard.setData(image.png, forType: .png)
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        let types = pasteboard.types ?? []
        guard ClipboardPrivacy.shouldRecord(types: types.map(\.rawValue)) else { return }
        if let text = pasteboard.string(forType: .string) {
            onContent(.text(text))
            return
        }
        // Copied files come with their Finder icon as a picture; that is not
        // what the user copied.
        guard !types.contains(.fileURL), let image = readImage(types: types) else { return }
        onContent(.image(image))
    }

    private func readImage(types: [NSPasteboard.PasteboardType]) -> ClipboardImage? {
        let limit = ClipboardHistory.maximumImageBytes
        var png: Data?
        if types.contains(.png), let data = pasteboard.data(forType: .png), data.count <= limit {
            png = data
        } else if types.contains(.tiff), let tiff = pasteboard.data(forType: .tiff), tiff.count <= limit * 4 {
            png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        }
        guard let png, png.count <= limit, let rep = NSBitmapImageRep(data: png) else { return nil }
        return ClipboardImage(png: png, pixelWidth: rep.pixelsWide, pixelHeight: rep.pixelsHigh)
    }
}
