import Foundation

/// All shelves and their tabs. A value type: every change goes through a method
/// here so the invariants (unique URLs per group, at least one group) hold.
public struct Library: Codable, Equatable, Sendable {
    public enum GroupOrder: String, Codable, CaseIterable, Sendable {
        case manual
        case name
        case recentlyChanged
        case newestFirst
        case size
    }

    public struct AddResult: Equatable, Sendable {
        public var added: [SavedTab] = []
        public var duplicates: [URL] = []
    }

    public static let currentVersion = 1

    public var version: Int
    public var groups: [TabGroup]
    public var groupOrder: GroupOrder
    public var lastUsedGroupID: UUID?

    public init(groups: [TabGroup] = [], groupOrder: GroupOrder = .manual) {
        self.version = Self.currentVersion
        self.groups = groups
        self.groupOrder = groupOrder
        ensureInbox()
    }

    // MARK: Queries

    public var orderedGroups: [TabGroup] {
        var result = groups
        switch groupOrder {
        case .manual:
            break
        case .name:
            result.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recentlyChanged:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .newestFirst:
            result.sort { $0.createdAt > $1.createdAt }
        case .size:
            result.sort { $0.tabs.count > $1.tabs.count }
        }
        return result.filter(\.isPinned) + result.filter { !$0.isPinned }
    }

    public var defaultGroupID: UUID {
        if let id = lastUsedGroupID, groups.contains(where: { $0.id == id }) { return id }
        return groups[0].id
    }

    public func group(_ id: UUID) -> TabGroup? {
        groups.first { $0.id == id }
    }

    public func groups(containing url: URL) -> [TabGroup] {
        groups.filter { $0.contains(url) }
    }

    public func search(_ query: String) -> [(group: TabGroup, tabs: [SavedTab])] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return orderedGroups.map { (group: $0, tabs: $0.sortedTabs) } }
        return orderedGroups.compactMap { group in
            let matches = group.sortedTabs.filter { tab in
                let haystack = [tab.displayTitle, tab.url.absoluteString, tab.note, group.name]
                    .joined(separator: " ")
                    .lowercased()
                return terms.allSatisfy { haystack.contains($0) }
            }
            return matches.isEmpty ? nil : (group: group, tabs: matches)
        }
    }

    // MARK: Groups

    @discardableResult
    public mutating func createGroup(named name: String, color: GroupColor? = nil) -> TabGroup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let palette = GroupColor.allCases
        let group = TabGroup(
            name: trimmed.isEmpty ? "Untitled" : String(trimmed.prefix(80)),
            color: color ?? palette[groups.count % palette.count]
        )
        groups.insert(group, at: 0)
        lastUsedGroupID = group.id
        return group
    }

    public mutating func updateGroup(_ id: UUID, _ change: (inout TabGroup) -> Void) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        change(&groups[index])
        groups[index].name = String(groups[index].name.prefix(80))
        groups[index].updatedAt = .now
    }

    public mutating func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        ensureInbox()
    }

    /// Moves a group before or after another one, switching to manual order.
    public mutating func moveGroup(_ id: UUID, relativeTo targetID: UUID, after: Bool) {
        guard id != targetID else { return }
        if groupOrder != .manual {
            groups = orderedGroups
            groupOrder = .manual
        }
        guard let from = groups.firstIndex(where: { $0.id == id }) else { return }
        var moving = groups.remove(at: from)
        guard let target = groups.firstIndex(where: { $0.id == targetID }) else {
            groups.insert(moving, at: from)
            return
        }
        moving.isPinned = groups[target].isPinned
        groups.insert(moving, at: after ? target + 1 : target)
    }

    // MARK: Tabs

    @discardableResult
    public mutating func add(_ pages: [PageReference], to groupID: UUID, at position: Int? = nil) -> AddResult {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return AddResult() }
        var result = AddResult()
        var known = Set(groups[index].tabs.map { URLNormalizer.identity(of: $0.url) })
        var insertAt = position.map { min(max(0, $0), groups[index].tabs.count) } ?? groups[index].tabs.count

        for page in pages where URLNormalizer.isSavable(page.url) {
            let key = URLNormalizer.identity(of: page.url)
            guard known.insert(key).inserted else {
                result.duplicates.append(page.url)
                continue
            }
            let tab = SavedTab(title: String(page.title.prefix(300)), url: page.url)
            groups[index].tabs.insert(tab, at: insertAt)
            insertAt += 1
            result.added.append(tab)
        }

        if !result.added.isEmpty { groups[index].updatedAt = .now }
        lastUsedGroupID = groupID
        return result
    }

    public mutating func updateTab(_ tabID: UUID, _ change: (inout SavedTab) -> Void) {
        for g in groups.indices {
            if let t = groups[g].tabs.firstIndex(where: { $0.id == tabID }) {
                change(&groups[g].tabs[t])
                groups[g].updatedAt = .now
                return
            }
        }
    }

    public mutating func removeTab(_ tabID: UUID) {
        for g in groups.indices {
            let before = groups[g].tabs.count
            groups[g].tabs.removeAll { $0.id == tabID }
            if groups[g].tabs.count != before { groups[g].updatedAt = .now }
        }
    }

    /// Moves a tab into `groupID`. Inside its own group this reorders and switches
    /// the group to manual order; into another group it is appended, or dropped if
    /// that group already has the same page.
    public mutating func moveTab(_ tabID: UUID, to groupID: UUID, before targetTabID: UUID? = nil) {
        guard
            let source = groups.firstIndex(where: { $0.tabs.contains { $0.id == tabID } }),
            let destination = groups.firstIndex(where: { $0.id == groupID }),
            let from = groups[source].tabs.firstIndex(where: { $0.id == tabID })
        else { return }

        if source == destination, groups[destination].sortOrder != .manual {
            groups[destination].tabs = groups[destination].sortedTabs
            groups[destination].sortOrder = .manual
        }
        let current = groups[source].tabs.firstIndex(where: { $0.id == tabID }) ?? from
        let tab = groups[source].tabs.remove(at: current)

        if source != destination, groups[destination].contains(tab.url) {
            groups[source].updatedAt = .now
            return
        }
        let insertAt =
            targetTabID.flatMap { id in groups[destination].tabs.firstIndex { $0.id == id } }
            ?? groups[destination].tabs.count
        groups[destination].tabs.insert(tab, at: insertAt)
        groups[source].updatedAt = .now
        groups[destination].updatedAt = .now
    }

    public mutating func markOpened(_ tabIDs: [UUID], at date: Date = .now) {
        let ids = Set(tabIDs)
        for g in groups.indices {
            for t in groups[g].tabs.indices where ids.contains(groups[g].tabs[t].id) {
                groups[g].tabs[t].lastOpenedAt = date
            }
        }
    }

    // MARK: Invariants

    private mutating func ensureInbox() {
        if groups.isEmpty {
            groups = [TabGroup(name: "Inbox", color: .blue)]
        }
        if let id = lastUsedGroupID, !groups.contains(where: { $0.id == id }) {
            lastUsedGroupID = nil
        }
    }

    /// Re-applies invariants after decoding data that may come from an older
    /// version or from an edited file.
    public mutating func repair() {
        version = Self.currentVersion
        for g in groups.indices {
            var seen = Set<String>()
            groups[g].tabs.removeAll { !URLNormalizer.isSavable($0.url) || !seen.insert(URLNormalizer.identity(of: $0.url)).inserted }
        }
        ensureInbox()
    }
}

/// A page coming from a browser, a paste or a drop, before it becomes a `SavedTab`.
public struct PageReference: Hashable, Sendable {
    public var url: URL
    public var title: String

    public init(url: URL, title: String = "") {
        self.url = url
        self.title = title
    }
}
