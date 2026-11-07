import AppKit
import Observation
import UniformTypeIdentifiers

/// A temporary place for files: drop them in, drag them out later.
/// Only references are kept, in memory; files are never copied or moved.
@MainActor
@Observable
final class ShelfModel {
    struct Item: Identifiable, Hashable {
        let url: URL
        var id: URL { url }
        var name: String { url.lastPathComponent }
    }

    private(set) var items: [Item] = []

    func add(_ urls: [URL]) {
        var seen = Set(items.map(\.url))
        let fresh = urls.filter { $0.isFileURL && seen.insert($0).inserted }
        items.insert(contentsOf: fresh.map(Item.init), at: 0)
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
            let url = folder.appending(path: "Image \(stamp).png")
            try png.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path(percentEncoded: false))
            add([url])
            return true
        } catch {
            return false
        }
    }

    func remove(_ item: Item) { items.removeAll { $0 == item } }
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
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func open(_ item: Item) {
        NSWorkspace.shared.open(item.url)
    }

    func airDrop(_ selection: [Item]) {
        let urls = (selection.isEmpty ? items : selection).map(\.url)
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls)
        else { return }
        service.perform(withItems: urls)
    }
}
