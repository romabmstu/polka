import AppKit
import Observation
import OSLog
import PolkaCore
import PolkaSystem

@MainActor
@Observable
final class TabsModel {
    enum SafariState: Equatable {
        case unknown, notRunning, notAuthorized, ready
    }

    private(set) var library = Library()
    private(set) var isLoaded = false
    /// Set when the file on disk could not be read; nothing is saved until the
    /// user decides what to do, so their data is never overwritten.
    private(set) var loadError: String?
    var selectedGroupID: UUID?
    var query = ""

    private(set) var currentPage: PageReference?
    private(set) var safariState: SafariState = .unknown

    @ObservationIgnored private let store: LibraryStore?
    @ObservationIgnored private let safari = SafariBridge()
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var undoSnapshot: Library?
    @ObservationIgnored private let log = Logger(subsystem: "Polka", category: "tabs")

    init() {
        store = (try? LibraryStore.defaultFileURL()).map(LibraryStore.init)
    }

    var selectedGroup: TabGroup? {
        selectedGroupID.flatMap(library.group) ?? library.orderedGroups.first
    }

    var currentPageGroups: [TabGroup] {
        currentPage.map { library.groups(containing: $0.url) } ?? []
    }

    // MARK: Loading and saving

    func load() async {
        guard let store else {
            loadError = String(localized: "Could not find the Application Support folder.")
            return
        }
        do {
            library = try await store.load()
            isLoaded = true
        } catch LibraryStore.StoreError.unsupportedVersion {
            loadError = String(localized: "Your tabs were saved by a newer version of Polka. Update Polka to open them.")
        } catch {
            log.error("Library unreadable, moved aside: \(error.localizedDescription, privacy: .public)")
            library = Library()
            isLoaded = true
            loadError = String(localized: "The tab library was damaged. A copy was kept next to it and a new one was started.")
        }
    }

    private func scheduleSave() {
        guard isLoaded, let store else { return }
        pendingSave?.cancel()
        let snapshot = library
        pendingSave = Task { [log] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do { try await store.save(snapshot) } catch {
                log.error("Saving library failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Flushes the pending write synchronously; called on quit.
    func saveNow() {
        guard isLoaded, let store, pendingSave != nil else { return }
        pendingSave?.cancel()
        let snapshot = library
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            try? await store.save(snapshot)
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }

    private func mutate(undoable: Bool = false, _ change: (inout Library) -> Void) {
        if undoable { undoSnapshot = library }
        change(&library)
        scheduleSave()
    }

    var canUndo: Bool { undoSnapshot != nil }

    func undo() {
        guard let snapshot = undoSnapshot else { return }
        undoSnapshot = nil
        library = snapshot
        scheduleSave()
    }

    // MARK: Safari

    func refreshCurrentPage() async {
        guard safari.isRunning else {
            safariState = .notRunning
            currentPage = nil
            return
        }
        do {
            currentPage = try await safari.currentTab()
            safariState = .ready
        } catch SafariBridge.Failure.notAuthorized {
            safariState = .notAuthorized
            currentPage = nil
        } catch {
            log.error("Reading Safari tabs failed: \(error.localizedDescription, privacy: .public)")
            currentPage = nil
        }
    }

    func openTabs() async throws -> [BrowserTab] {
        try await safari.tabs()
    }

    // MARK: Editing

    @discardableResult
    func add(_ pages: [PageReference], to groupID: UUID, at position: Int? = nil) -> Library.AddResult {
        var result = Library.AddResult()
        mutate { result = $0.add(pages, to: groupID, at: position) }
        return result
    }

    @discardableResult
    func createGroup(named name: String, color: GroupColor? = nil) -> UUID {
        var id = UUID()
        mutate { id = $0.createGroup(named: name, color: color).id }
        selectedGroupID = id
        return id
    }

    func updateGroup(_ id: UUID, _ change: (inout TabGroup) -> Void) {
        mutate { $0.updateGroup(id, change) }
    }

    func deleteGroup(_ id: UUID) {
        mutate(undoable: true) { $0.deleteGroup(id) }
        if selectedGroupID == id { selectedGroupID = nil }
    }

    func moveGroup(_ id: UUID, relativeTo target: UUID, after: Bool) {
        mutate { $0.moveGroup(id, relativeTo: target, after: after) }
    }

    func setGroupOrder(_ order: Library.GroupOrder) {
        mutate { $0.groupOrder = order }
    }

    func updateTab(_ id: UUID, _ change: (inout SavedTab) -> Void) {
        mutate { $0.updateTab(id, change) }
    }

    func removeTab(_ id: UUID) {
        mutate(undoable: true) { $0.removeTab(id) }
    }

    func moveTab(_ id: UUID, to groupID: UUID, before target: UUID? = nil) {
        mutate { $0.moveTab(id, to: groupID, before: target) }
    }

    // MARK: Opening

    func open(_ tab: SavedTab) {
        mutate { $0.markOpened([tab.id]) }
        NSWorkspace.shared.open(tab.url)
    }

    func openGroup(_ group: TabGroup, inNewWindow: Bool, removeAfterwards: Bool = false) async {
        let tabs = group.sortedTabs
        guard !tabs.isEmpty else { return }
        mutate(undoable: removeAfterwards) { library in
            library.markOpened(tabs.map(\.id))
            if removeAfterwards { library.updateGroup(group.id) { $0.tabs.removeAll() } }
        }
        do {
            try await safari.open(tabs.map(\.url), inNewWindow: inNewWindow)
        } catch {
            for tab in tabs { NSWorkspace.shared.open(tab.url) }
        }
    }
}
