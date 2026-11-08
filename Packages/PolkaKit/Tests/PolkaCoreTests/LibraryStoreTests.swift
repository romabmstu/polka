import Foundation
import Testing

@testable import PolkaCore

@Suite struct LibraryStoreTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "polka-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test func roundTripsAndRestrictsPermissions() async throws {
        let store = LibraryStore(fileURL: directory.appending(path: "library.json"))
        var library = Library()
        library.add([PageReference(url: URL(string: "https://swift.org")!, title: "Swift")], to: library.groups[0].id)

        try await store.save(library)
        let loaded = try await store.load()

        #expect(loaded.groups.map(\.id) == library.groups.map(\.id))
        #expect(loaded.groups[0].tabs.map(\.url) == library.groups[0].tabs.map(\.url))
        #expect(loaded.lastUsedGroupID == library.lastUsedGroupID)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path(percentEncoded: false))
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func missingFileGivesEmptyLibrary() async throws {
        let store = LibraryStore(fileURL: directory.appending(path: "none.json"))
        #expect(try await store.load().groups.count == 1)
    }

    @Test func keepsPreviousLibraryBeforeSaving() async throws {
        let store = LibraryStore(fileURL: directory.appending(path: "library.json"))
        var library = Library()
        library.add([PageReference(url: URL(string: "https://example.com")!)], to: library.groups[0].id)
        try await store.save(library)
        library.removeTab(library.groups[0].tabs[0].id)
        try await store.save(library)
        let recovery = directory.appending(path: "Recovery")
        let backup = try #require(FileManager.default.contentsOfDirectory(at: recovery, includingPropertiesForKeys: nil).first)
        let recovered = try await LibraryStore(fileURL: backup).load()
        #expect(recovered.groups[0].tabs.count == 1)
    }

    @Test func loadsOlderLibrariesBeforeAddingNestedGroups() async throws {
        let url = directory.appending(path: "library.json")
        let store = LibraryStore(fileURL: url)
        var old = Library()
        old.add([PageReference(url: URL(string: "https://example.com")!)], to: old.groups[0].id)
        try await store.save(old)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["version"] = 1
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        var loaded = try await store.load()
        let parent = loaded.groups[0].id
        let child = loaded.createGroup(named: "Child", parentID: parent)
        try await store.save(loaded)
        let restored = try await store.load()
        #expect(restored.group(parent)?.tabs.count == 1)
        #expect(restored.group(child.id)?.parentID == parent)
        #expect(restored.version == 2)
    }

    @Test func corruptFileIsMovedAsideNotOverwritten() async throws {
        let url = directory.appending(path: "library.json")
        try Data("{ not json".utf8).write(to: url)
        let store = LibraryStore(fileURL: url)

        await #expect(throws: LibraryStore.StoreError.corruptFileQuarantined) { try await store.load() }

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(leftovers.contains { $0.hasPrefix("library.unreadable-") })
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func readFailureDoesNotQuarantineTheSource() async throws {
        let store = LibraryStore(fileURL: directory)
        await #expect(throws: (any Error).self) { try await store.load() }
        #expect(FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
    }

    @Test func newerFormatIsLeftUntouched() async throws {
        let url = directory.appending(path: "library.json")
        try Data(#"{"version": 99, "groups": []}"#.utf8).write(to: url)
        let store = LibraryStore(fileURL: url)

        await #expect(throws: LibraryStore.StoreError.unsupportedVersion(99)) { try await store.load() }
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func saveDoesNotOverwriteNewerFormatWrittenAfterLoad() async throws {
        let url = directory.appending(path: "library.json")
        let store = LibraryStore(fileURL: url)
        let loaded = try await store.load()
        let newer = Data(#"{"version": 99, "groups": []}"#.utf8)
        try newer.write(to: url)
        await #expect(throws: LibraryStore.StoreError.unsupportedVersion(99)) { try await store.save(loaded) }
        #expect(try Data(contentsOf: url) == newer)
    }

    @Test func olderSaveCannotOverwriteNewerSnapshot() async throws {
        let store = LibraryStore(fileURL: directory.appending(path: "library.json"))
        var old = Library()
        let group = old.groups[0].id
        old.add([PageReference(url: URL(string: "https://example.com/old")!)], to: group)
        var newer = old
        newer.add([PageReference(url: URL(string: "https://example.com/new")!)], to: group)
        try await store.save(newer, generation: 2)
        try await store.save(old, generation: 1)
        #expect(try await store.load().group(group)?.tabs.count == 2)
    }
}
