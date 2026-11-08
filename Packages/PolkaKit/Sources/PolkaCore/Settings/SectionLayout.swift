import Foundation

/// Restores the user's choice and order of panel sections across versions.
public enum SectionLayout {
    /// - Parameters:
    ///   - saved: section IDs in the user's order, or `nil` if never saved.
    ///   - known: sections the user has already been shown, or `nil` for a
    ///     layout saved before this was recorded (then `original` is used).
    ///   - all: every section this version has, in default order.
    ///   - original: the sections of the first versions.
    /// - Returns: the saved layout without IDs this version doesn't know
    ///   (saved by a newer version), plus sections the user hasn't seen yet,
    ///   added once at the end so updates don't hide new features.
    public static func restore(saved: [String]?, known: [String]?, all: [String], original: [String]) -> [String] {
        guard let saved else { return all }
        let available = Set(all)
        var result: [String] = []
        for id in saved where available.contains(id) && !result.contains(id) {
            result.append(id)
        }
        let seen = Set(known ?? original)
        for id in all where !seen.contains(id) && !result.contains(id) {
            result.append(id)
        }
        return result.isEmpty ? all : result
    }

    /// What to store as "known" after a launch: everything seen before plus
    /// everything this version has. Going back to an older version must not
    /// forget sections the newer one already showed.
    public static func known(before: [String]?, all: [String], original: [String]) -> [String] {
        var result = before ?? original
        for id in all where !result.contains(id) {
            result.append(id)
        }
        return result
    }
}
