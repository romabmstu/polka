import AppKit
import Observation
import OSLog
import PolkaCore
import PolkaSystem

@MainActor
@Observable
final class TabsModel {
    enum BrowserState: Equatable {
        case unknown, noBrowser, notAuthorized(Browser), ready(Browser)
    }

    private(set) var library = Library()
    private(set) var isLoaded = false
    /// Set when the file on disk could not be read; nothing is saved until the
    /// user decides what to do, so their data is never overwritten.
    private(set) var loadError: String?
    var selectedGroupID: UUID?
    var query = ""

    private(set) var currentPage: PageReference?
    private(set) var browserState: BrowserState = .unknown
    /// Browsers the user can be asked about, most recently used first.
    @ObservationIgnored private var recentBrowsers: [String] = []
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    @ObservationIgnored private let store: LibraryStore?
    @ObservationIgnored private let browsers = BrowserBridge()
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var undoSnapshot: Library?
    @ObservationIgnored private let log = Logger(subsystem: "Polka", category: "tabs")

    init() {
        store = (try? LibraryStore.defaultFileURL()).map(LibraryStore.init)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let id = app?.bundleIdentifier, Browser(bundleIdentifier: id) != nil else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.recentBrowsers.removeAll { $0 == id }
                self.recentBrowsers.insert(id, at: 0)
            }
        }
    }

    var hasBrowserAccess: Bool {
        if case .ready = browserState { return true }
        return false
    }

    var currentBrowser: Browser? {
        switch browserState {
        case .ready(let browser), .notAuthorized(let browser): browser
        default: nil
        }
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
        } catch LibraryStore.StoreError.corruptFileQuarantined {
            log.error("Library unreadable, moved aside")
            library = Library()
            isLoaded = true
            loadError = String(localized: "The tab library was damaged. A copy was kept next to it and a new one was started.")
        } catch {
            log.error("Could not read library: \(error.localizedDescription, privacy: .public)")
            loadError = String(localized: "Could not read the tab library. Your changes will not be saved.")
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

    // MARK: Browsers

    /// Reads the page open in the frontmost (or most recently used) browser.
    @discardableResult
    func refreshCurrentPage() async -> PageReference? {
        await captureFrontWindow()?.current.first
    }

    /// The current tab and the rest of the front window of the browser the
    /// user is most likely talking about.
    func captureFrontWindow() async -> SaveRequest? {
        guard let browser = BrowserBridge.preferredBrowser(recent: recentBrowsers) else {
            browserState = .noBrowser
            currentPage = nil
            return nil
        }
        do {
            let front = try await browsers.tabs(in: browser).filter { $0.window == 1 }
            browserState = .ready(browser)
            currentPage = front.first(where: \.isCurrent)?.page
            guard let page = currentPage else { return nil }
            return SaveRequest(source: browser.name, current: [page], window: front.map(\.page))
        } catch BrowserBridge.Failure.notAuthorized(let denied) {
            browserState = .notAuthorized(denied)
            currentPage = nil
        } catch {
            log.error("Reading \(browser.name, privacy: .public) tabs failed: \(error.localizedDescription, privacy: .public)")
            browserState = .ready(browser)
            currentPage = nil
        }
        return nil
    }

    /// Group IDs in the order the save picker offers them: the last one used
    /// first, then the library order.
    var saveTargets: [TabGroup] {
        var groups = library.orderedGroups
        if let last = library.lastUsedGroupID, let index = groups.firstIndex(where: { $0.id == last }) {
            groups.insert(groups.remove(at: index), at: 0)
        }
        return groups
    }

    // MARK: Editing

    @discardableResult
    func add(_ pages: [PageReference], to groupID: UUID, at position: Int? = nil) -> Library.AddResult {
        var result = Library.AddResult()
        mutate { result = $0.add(pages, to: groupID, at: position) }
        return result
    }

    @discardableResult
    func createGroup(named name: String, color: GroupColor? = nil, parentID: UUID? = nil) -> UUID {
        var id = UUID()
        mutate { id = $0.createGroup(named: name, color: color, parentID: parentID).id }
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

    func moveGroup(_ id: UUID, into parentID: UUID) {
        mutate { $0.moveGroup(id, into: parentID) }
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
        guard URLNormalizer.isSavable(tab.url) else { return }
        mutate { $0.markOpened([tab.id]) }
        NSWorkspace.shared.open(tab.url)
    }

    func openInNewWindow(_ tab: SavedTab) async {
        guard URLNormalizer.isSavable(tab.url) else { return }
        mutate { $0.markOpened([tab.id]) }
        do {
            try await browsers.open([tab.url], in: currentBrowser ?? .safari, inNewWindow: true)
        } catch {
            NSWorkspace.shared.open(tab.url)
        }
    }

    func openGroup(_ group: TabGroup, inNewWindow: Bool, removeAfterwards: Bool = false) async {
        let tabs = group.sortedTabs.filter { URLNormalizer.isSavable($0.url) }
        guard !tabs.isEmpty else { return }
        mutate(undoable: removeAfterwards) { library in
            library.markOpened(tabs.map(\.id))
            if removeAfterwards { library.updateGroup(group.id) { $0.tabs.removeAll() } }
        }
        do {
            try await browsers.open(tabs.map(\.url), in: currentBrowser ?? .safari, inNewWindow: inNewWindow)
        } catch {
            for tab in tabs { NSWorkspace.shared.open(tab.url) }
        }
    }
}
