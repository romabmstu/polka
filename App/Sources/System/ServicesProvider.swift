import AppKit
import PolkaCore

/// Handles "Save to Polka…" in the Services menu, which macOS shows in the
/// context menu of selected text and links in Safari, Chrome, Arc and most
/// other apps. Nothing but web links is taken from the pasteboard.
@MainActor
final class ServicesProvider: NSObject {
    private let onPages: ([PageReference], String?) -> Void

    init(onPages: @escaping ([PageReference], String?) -> Void) {
        self.onPages = onPages
    }

    /// Selector name matches `NSMessage` in Info.plist.
    @objc func saveToPolka(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let source = NSWorkspace.shared.frontmostApplication?.localizedName
        onPages(Self.pages(from: pasteboard), source)
    }

    static func pages(from pasteboard: NSPasteboard) -> [PageReference] {
        // Selections from web pages carry HTML with the real link targets,
        // which plain text loses.
        if let html = pasteboard.string(forType: .html) {
            let pages = LinkExtractor.pages(inHTML: String(html.prefix(300_000)))
            if !pages.isEmpty { return pages }
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let pages = urls.filter(URLNormalizer.isSavable).map { PageReference(url: $0) }
            if !pages.isEmpty { return pages }
        }
        if let text = pasteboard.string(forType: .string) {
            return LinkExtractor.pages(in: String(text.prefix(1_000_000)))
        }
        return []
    }
}
