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
    private var lastSaveGeneration: Int?

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

    public func save(_ library: Library, generation: Int? = nil) throws {
        if let generation, let lastSaveGeneration, generation <= lastSaveGeneration { return }
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var updated = library
        updated.version = Library.currentVersion
        let data = try Self.makeEncoder().encode(updated)
        let recovery = directory.appending(path: "Recovery", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            // A newer instance may have written the file since this instance
            // loaded it. Do not overwrite a format we cannot understand.
            let existing = try Data(contentsOf: fileURL)
            if let header = try? Self.makeDecoder().decode(VersionHeader.self, from: existing),
               header.version > Library.currentVersion {
                throw StoreError.unsupportedVersion(header.version)
            }
            try fileManager.createDirectory(at: recovery, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let backup = recovery.appending(path: "auto-\(UUID().uuidString).json")
            try fileManager.copyItem(at: fileURL, to: backup)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path(percentEncoded: false))
        }
        try data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path(percentEncoded: false))
        if let generation { lastSaveGeneration = generation }
        if let files = try? fileManager.contentsOfDirectory(at: recovery, includingPropertiesForKeys: [.creationDateKey]) {
            let backups = files.filter { $0.lastPathComponent.hasPrefix("auto-") }.sorted {
                ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
                    > ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
            }
            for old in backups.dropFirst(20) { try? fileManager.removeItem(at: old) }
        }
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
