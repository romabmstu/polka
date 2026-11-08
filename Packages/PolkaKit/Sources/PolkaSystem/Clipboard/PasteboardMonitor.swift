import AppKit
import PolkaCore

/// Watches the general pasteboard for new text and pictures.
///
/// macOS has no change notification for the pasteboard, so this polls
/// `changeCount` (a cheap integer read) twice a second. Content marked as
/// concealed or transient (passwords, one-time codes) is never read.
/// Pictures are copied off the pasteboard on the main thread, which is fast,
/// and converted in the background, which can take a while for big ones.
@MainActor
public final class PasteboardMonitor {
    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?
    /// Changes whenever monitoring stops, so a picture still being prepared
    /// is dropped instead of landing in a history the user just turned off.
    private var session = 0
    /// Keeps the TIFF provider for the picture Polka last put on the pasteboard.
    private var tiffProvider: TIFFProvider?
    public enum Content {
        case text(String)
        /// A picture and when it was copied.
        case image(ClipboardImage, copiedAt: Date)
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
        session += 1
    }

    /// Puts text the user picked from history back on the pasteboard without
    /// recording it again.
    public func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    /// Puts a picture from history back on the pasteboard as PNG. Apps that
    /// only paste TIFF get one converted when they ask for it.
    public func copy(_ image: ClipboardImage) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(image.png, forType: .png)
        let provider = TIFFProvider(png: image.png)
        if item.setDataProvider(provider, forTypes: [.tiff]) { tiffProvider = provider }
        pasteboard.writeObjects([item])
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
        guard !types.contains(.fileURL), let source = readImageSource(types: types) else { return }
        let copiedAt = Date.now
        let session = self.session
        Task.detached(priority: .utility) { [weak self] in
            guard let image = ClipboardImageCodec.makeImage(from: source) else { return }
            await self?.deliver(image, copiedAt: copiedAt, session: session)
        }
    }

    private func deliver(_ image: ClipboardImage, copiedAt: Date, session: Int) {
        guard session == self.session, isRunning else { return }
        onContent(.image(image, copiedAt: copiedAt))
    }

    /// The picture's bytes, if they are small enough to be worth converting.
    private func readImageSource(types: [NSPasteboard.PasteboardType]) -> ClipboardImageCodec.Source? {
        let limit = ClipboardHistory.maximumImageBytes
        if types.contains(.png), let data = pasteboard.data(forType: .png) {
            return data.count <= limit ? .png(data) : nil
        }
        // Uncompressed TIFF is several times larger than the PNG it becomes.
        if types.contains(.tiff), let tiff = pasteboard.data(forType: .tiff), tiff.count <= limit * 4 {
            return .other(tiff)
        }
        return nil
    }
}

/// Converts a PNG to TIFF only when an app pastes TIFF.
private final class TIFFProvider: NSObject, NSPasteboardItemDataProvider {
    private let png: Data

    init(png: Data) {
        self.png = png
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .tiff, let tiff = ClipboardImageCodec.tiffData(fromPNG: png) else { return }
        item.setData(tiff, forType: .tiff)
    }
}
