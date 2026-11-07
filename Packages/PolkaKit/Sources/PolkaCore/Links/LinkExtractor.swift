import Foundation

/// Pulls web links out of pasted or dropped text: bare URLs, Markdown links and
/// OneTab exports (`https://… | Title`). Order is preserved, duplicates removed.
public enum LinkExtractor {
    public static func pages(in text: String) -> [PageReference] {
        var result: [PageReference] = []
        var seen = Set<String>()

        func append(_ raw: Substring, title: Substring = "") {
            guard let url = URL(string: trimTrailingPunctuation(String(raw))), URLNormalizer.isSavable(url) else { return }
            guard seen.insert(URLNormalizer.identity(of: url)).inserted else { return }
            result.append(PageReference(url: url, title: title.trimmingCharacters(in: .whitespaces)))
        }

        var remaining = text
        // Markdown first, so its URL is not picked up again as a bare link.
        for match in remaining.matches(of: markdownLink) {
            append(match.output.url, title: match.output.title)
        }
        remaining = remaining.replacing(markdownLink, with: " ")

        for line in remaining.split(whereSeparator: \.isNewline) {
            if let match = line.wholeMatch(of: oneTabLine) {
                append(match.output.url, title: match.output.title)
                continue
            }
            let urls = line.matches(of: bareURL)
            for match in urls {
                var title: Substring = ""
                if urls.count == 1 {
                    title = line.replacingCharacters(in: match.range, with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: " \t-–—:|*•"))[...]
                }
                append(match.output, title: title)
            }
        }
        return result
    }

    /// Links from an HTML fragment, such as a selection copied from a web page.
    /// Anchor text becomes the title. Relative links are skipped: a fragment
    /// carries no base address to resolve them against.
    public static func pages(inHTML html: String) -> [PageReference] {
        var result: [PageReference] = []
        var seen = Set<String>()
        for match in html.matches(of: anchor) {
            let raw = decodeEntities(String(match.output.href)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: raw), URLNormalizer.isSavable(url) else { continue }
            guard seen.insert(URLNormalizer.identity(of: url)).inserted else { continue }
            let text = decodeEntities(String(match.output.body).replacing(tag, with: ""))
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            result.append(PageReference(url: url, title: text))
        }
        return result
    }

    private static func decodeEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "]
        var s = string
        for (entity, value) in named { s = s.replacingOccurrences(of: entity, with: value) }
        return s
    }

    private static func trimTrailingPunctuation(_ string: String) -> String {
        var s = string
        while let last = s.last, ").,;:!?]>»\"'".contains(last) {
            // Keep a closing parenthesis that balances one inside the URL (Wikipedia-style).
            if last == ")", s.filter({ $0 == "(" }).count >= s.filter({ $0 == ")" }).count { break }
            s.removeLast()
        }
        return s
    }

    nonisolated(unsafe) private static let markdownLink = /\[(?<title>[^\]]*)\]\((?<url>https?:\/\/[^\s)]+)\)/
    nonisolated(unsafe) private static let oneTabLine = /\s*(?<url>https?:\/\/\S+)\s+\|\s+(?<title>.+)/
    nonisolated(unsafe) private static let anchor = /<a\s[^>]*?href\s*=\s*["'](?<href>[^"']+)["'][^>]*>(?<body>.*?)<\/a>/
        .ignoresCase().dotMatchesNewlines()
    nonisolated(unsafe) private static let tag = /<[^>]*>/
    nonisolated(unsafe) private static let bareURL = /(?:https?|file):\/\/[^\s<>"']+/
}
