import Foundation

/// Reads and writes the library as a single JSON file.
///
/// Writes are atomic (temporary file + rename) and the file is created readable
/// by the current user only. A file that fails to decode is never overwritten:
/// it is moved aside so a bad edit or a future format cannot destroy data.
public actor LibraryStore {
    public enum StoreError: Error, Equatable {
        case unsupportedVersion(Int)
        case corruptFileQuarantined
    }

    public nonisolated let fileURL: URL
    private let fileManager = FileManager()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/<folder>/library.json`
    public static func defaultFileURL(folder: String = "Polka") throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appending(path: folder, directoryHint: .isDirectory).appending(path: "library.json")
    }

    public func load() throws -> Library {
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return Library() }
        let data = try Data(contentsOf: fileURL)

        // Written by a newer Polka: leave the file alone and refuse to load,
        // so this older build cannot save over it.
        if let header = try? Self.makeDecoder().decode(VersionHeader.self, from: data),
            header.version > Library.currentVersion
        {
            throw StoreError.unsupportedVersion(header.version)
        }

        do {
            var library = try Self.makeDecoder().decode(Library.self, from: data)
            library.repair()
            return library
        } catch {
            try quarantineUnreadableFile()
            throw StoreError.corruptFileQuarantined
        }
    }

    public func save(_ library: Library) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try Self.makeEncoder().encode(library)
        try data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path(percentEncoded: false))
    }

    private func quarantineUnreadableFile() throws {
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let backup = fileURL.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
        try fileManager.moveItem(at: fileURL, to: backup)
    }

    private struct VersionHeader: Decodable {
        var version: Int
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
