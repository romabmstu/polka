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
    nonisolated(unsafe) private static let bareURL = /(?:https?|file):\/\/[^\s<>"']+/
}
