import Foundation

public struct TabGroup: Identifiable, Hashable, Codable, Sendable {
    public enum SortOrder: String, Codable, CaseIterable, Sendable {
        case manual
        case title
        case newestFirst
        case site
        case recentlyOpened
    }

    public var id: UUID
    public var name: String
    public var color: GroupColor
    public var isPinned: Bool
    public var sortOrder: SortOrder
    public var createdAt: Date
    public var updatedAt: Date
    /// Stored in manual order; `sortedTabs` applies `sortOrder` on top.
    public var tabs: [SavedTab]

    public init(
        id: UUID = UUID(),
        name: String,
        color: GroupColor = .blue,
        isPinned: Bool = false,
        sortOrder: SortOrder = .manual,
        createdAt: Date = .now,
        tabs: [SavedTab] = []
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.isPinned = isPinned
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.tabs = tabs
    }

    public var sortedTabs: [SavedTab] {
        switch sortOrder {
        case .manual:
            tabs
        case .title:
            tabs.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        case .newestFirst:
            tabs.sorted { $0.addedAt > $1.addedAt }
        case .site:
            tabs.sorted {
                let order = $0.site.localizedStandardCompare($1.site)
                if order != .orderedSame { return order == .orderedAscending }
                return $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
            }
        case .recentlyOpened:
            tabs.sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
        }
    }

    public func contains(_ url: URL) -> Bool {
        let key = URLNormalizer.identity(of: url)
        return tabs.contains { URLNormalizer.identity(of: $0.url) == key }
    }
}

public enum GroupColor: String, Codable, CaseIterable, Sendable {
    case blue, green, orange, red, purple, teal, pink, gray
}
