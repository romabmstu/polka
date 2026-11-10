import AppKit
import Observation
import PolkaCore
import UniformTypeIdentifiers

/// A temporary place for files: drop them in, drag them out later.
/// Only references are kept, in memory; files are never copied or moved.
@MainActor
@Observable
final class ShelfModel {
    struct Item: Identifiable, Hashable {
        let id: UUID
        fileprivate(set) var url: URL
        /// Finds the file again after it was renamed or moved.
        fileprivate let bookmark: Data?
        /// The file was deleted, or its disk is not connected.
        fileprivate(set) var isMissing = false

        var name: String { url.lastPathComponent }
    }

    private(set) var items: [Item] = []

    func add(_ urls: [URL]) {
        var seen = Set(items.map(\.url))
        let fresh = urls.filter(\.isFileURL)
            .map { URLNormalizer.pathForm(of: $0).standardizedFileURL }
            .filter { seen.insert($0).inserted }
        items.insert(contentsOf: fresh.map { Item(id: UUID(), url: $0, bookmark: try? $0.bookmarkData()) }, at: 0)
        if items.count > 40 { items.removeLast(items.count - 40) }
    }

    /// Writes a picture from clipboard history to a private temporary folder
    /// so it can be dragged out or sent with AirDrop like any file. Only done
    /// when the user asks; macOS clears the folder on its own.
    @discardableResult
    func add(png: Data, copiedAt date: Date) -> Bool {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Shelf", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
            let stamp = formatter.string(from: date)
            // Two pictures copied within the same second must not share a file.
            var url = folder.appending(path: "Image \(stamp).png")
            var copy = 2
            while let existing = try? Data(contentsOf: url), existing != png {
                url = folder.appending(path: "Image \(stamp) \(copy).png")
                copy += 1
            }
            try png.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path(percentEncoded: false))
            add([url])
            return true
        } catch {
            return false
        }
    }

    /// Catches up with files renamed, moved or deleted since they were added,
    /// so a tile never shows or hands out a name the file no longer has.
    func refresh() {
        let current = items.map { Self.located($0) }
        if current != items { items = current }
    }

    private static func located(_ item: Item) -> Item {
        var item = item
        if let bookmark = item.bookmark {
            var isStale = false
            let found = try? URL(
                resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &isStale)
            if let found { item.url = found.standardizedFileURL }
        }
        let path = item.url.path(percentEncoded: false)
        // A file in the Trash still exists, but the user has thrown it away.
        item.isMissing = !FileManager.default.fileExists(atPath: path) || path.contains("/.Trash")
        return item
    }

    /// The item as it is right now, or nil when its file is gone.
    private func current(_ item: Item) -> Item? {
        refresh()
        return items.first { $0.id == item.id && !$0.isMissing }
    }

    /// Hands the receiving app the file itself, the way Finder does, so the
    /// name and contents arrive untouched. A provider built from the file's
    /// contents becomes a file promise, and the receiver names its own copy.
    func dragProvider(for item: Item) -> NSItemProvider {
        guard let item = current(item) else { return NSItemProvider() }
        return NSItemProvider(object: item.url as NSURL)
    }

    func remove(_ item: Item) { items.removeAll { $0.id == item.id } }
    func clear() { items.removeAll() }

    func icon(for item: Item) -> NSImage {
        NSWorkspace.shared.icon(forFile: item.url.path(percentEncoded: false))
    }

    func size(of item: Item) -> String? {
        guard
            let values = try? item.url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
            values.isDirectory != true, let bytes = values.fileSize
        else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    func reveal(_ item: Item) {
        guard let item = current(item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func open(_ item: Item) {
        guard let item = current(item) else { return }
        NSWorkspace.shared.open(item.url)
    }

    func airDrop(_ selection: [Item]) {
        refresh()
        let chosen = Set(selection.map(\.id))
        let urls = items.filter { !$0.isMissing && (chosen.isEmpty || chosen.contains($0.id)) }.map(\.url)
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls)
        else { return }
        service.perform(withItems: urls)
    }
}
