import Foundation

/// What a bug report needs to know about the Mac and Polka's setup. Holds no
/// personal data: no tabs, events, clipboard contents or VPN names.
public struct Diagnostics: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var name: String
        public var value: String

        public init(_ name: String, _ value: String) {
            self.name = name
            self.value = value
        }
    }

    /// "0.1.0 (46)".
    public var appVersion: String
    /// "macOS 26.1 (25B78), Mac15,3, Apple silicon".
    public var system: String
    /// Everything else, in the order it is shown.
    public var items: [Item]

    public init(appVersion: String, system: String, items: [Item]) {
        self.appVersion = appVersion
        self.system = system
        self.items = items
    }

    /// Plain text for the clipboard and the report form.
    public var text: String {
        (["Polka: \(appVersion)", "System: \(system)"] + items.map { "\($0.name): \($0.value)" })
            .joined(separator: "\n")
    }
}

/// Links to a pre-filled bug report on GitHub. The issue form takes its field
/// values from the query string, keyed by field id.
public enum IssueLink {
    public static let newIssue = URL(string: "https://github.com/romabmstu/polka/issues/new")!
    /// GitHub and browsers handle URLs well beyond this; it leaves headroom.
    public static let maximumLength = 7_000

    public static func bugReport(title: String, what: String, diagnostics: Diagnostics, details: String? = nil) -> URL {
        var fields: [(String, String)] = [
            ("template", "bug_report.yml"),
            ("title", title),
            ("version", diagnostics.appVersion),
            ("macos", diagnostics.system),
            ("what", what),
            ("diagnostics", diagnostics.text),
        ]
        if let details, !details.isEmpty { fields.append(("logs", details)) }

        // Long fields are trimmed from the end, the least important first,
        // until the address fits.
        var url = make(fields)
        for key in ["logs", "diagnostics", "what"] {
            guard let index = fields.firstIndex(where: { $0.0 == key }) else { continue }
            while url.absoluteString.count > maximumLength, fields[index].1.count > 200 {
                let value = fields[index].1
                let overflow = url.absoluteString.count - maximumLength
                // Percent-encoding can triple a character, so cut generously.
                let keep = max(200, value.count - max(overflow / 3, 1) - 40)
                // Already at the floor: move on to the next field.
                if keep + 2 >= value.count { break }
                fields[index].1 = String(value.prefix(keep)) + "\n…"
                url = make(fields)
            }
        }
        return url
    }

    private static func make(_ fields: [(String, String)]) -> URL {
        // Only unreserved characters stay literal; "+" in particular must be
        // encoded or it would come back as a space.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let query = fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }
        .joined(separator: "&")
        return URL(string: newIssue.absoluteString + "?" + query) ?? newIssue
    }
}
