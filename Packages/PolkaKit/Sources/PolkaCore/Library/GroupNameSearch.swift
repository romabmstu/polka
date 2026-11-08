import Foundation

/// Filtering groups by name while the user types in the save picker.
public enum GroupNameSearch {
    public static let maximumNameLength = 80

    /// Groups whose name contains `query`, and the name to offer for a new
    /// group when no group already has exactly that name (ignoring case and
    /// accents). An empty query lists every group and offers nothing new.
    public static func results<Group>(
        in groups: [Group], name: (Group) -> String, query: String
    ) -> (matches: [Group], newGroupName: String?) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (groups, nil) }
        let matches = groups.filter { name($0).localizedStandardContains(trimmed) }
        let exists = groups.contains {
            name($0).compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        return (matches, exists ? nil : String(trimmed.prefix(maximumNameLength)))
    }
}
