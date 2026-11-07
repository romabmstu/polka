import Foundation

/// A web page the user put on a shelf.
public struct SavedTab: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var url: URL
    public var note: String
    public var addedAt: Date
    public var lastOpenedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        note: String = "",
        addedAt: Date = .now,
        lastOpenedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.note = note
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
    }

    /// Host without the `www.` prefix, used for display and for sorting by site.
    public var site: String {
        guard let host = url.host(percentEncoded: false) else { return url.scheme ?? "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Title to show when the page did not report one.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? URLNormalizer.readableForm(of: url) : trimmed
    }
}
