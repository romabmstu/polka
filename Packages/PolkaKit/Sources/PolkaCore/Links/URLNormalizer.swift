import Foundation

public enum URLNormalizer {
    private static let savableSchemes: Set<String> = ["http", "https", "file"]

    /// Only plain web pages and local files are kept. Anything else
    /// (`javascript:`, `data:`, app schemes) is rejected on purpose.
    public static func isSavable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), savableSchemes.contains(scheme) else { return false }
        if scheme == "file" { return url.isFileURL }
        return url.host(percentEncoded: false)?.isEmpty == false && url.absoluteString.count <= 8_192
    }

    /// Key used to detect duplicates: case-insensitive scheme and host,
    /// no trailing slash on bare paths, fragment preserved (single-page apps route with it).
    public static func identity(of url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.port == 80 && components.scheme == "http" { components.port = nil }
        if components.port == 443 && components.scheme == "https" { components.port = nil }
        if components.path.hasSuffix("/") && components.query == nil && components.fragment == nil {
            components.path.removeLast()
        }
        return components.string ?? url.absoluteString
    }

    /// `example.com/docs/page` — for places where a title is missing.
    public static func readableForm(of url: URL) -> String {
        if url.isFileURL { return url.lastPathComponent }
        var host = url.host(percentEncoded: false) ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = url.path(percentEncoded: false)
        if path.hasSuffix("/") { path.removeLast() }
        return host + path
    }

    /// Accepts what people type into an address field: adds `https://` when the
    /// scheme is missing and returns `nil` for anything that is not savable.
    public static func url(fromUserInput input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: candidate), isSavable(url) else { return nil }
        return url
    }
}
