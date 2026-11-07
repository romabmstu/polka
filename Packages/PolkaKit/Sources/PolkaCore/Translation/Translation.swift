import Foundation

/// Decides which way to translate. The user picks two languages; text in one
/// of them goes into the other, and text in any third language goes into the
/// first one, which is normally their own.
public enum TranslationRoute {
    /// Longer input is cut: the panel is for words, sentences and paragraphs.
    public static let maximumLength = 5_000

    /// `pt-BR` → `pt`, `zh-Hans` → `zh`.
    public static func baseCode(_ identifier: String) -> String {
        String(identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "").lowercased()
    }

    public static func target(detected: String?, primary: String, secondary: String) -> String {
        guard let detected else { return secondary }
        return baseCode(detected) == baseCode(primary) ? secondary : primary
    }

    /// Trimmed text worth sending to the translator, or nil.
    public static func prepare(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumLength))
    }
}

/// Recent translations, newest first, in memory only.
public struct TranslationHistory: Sendable, Equatable {
    public struct Entry: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let text: String
        public let translation: String
        public let source: String?
        public let target: String

        public init(id: UUID = UUID(), text: String, translation: String, source: String?, target: String) {
            self.id = id
            self.text = text
            self.translation = translation
            self.source = source
            self.target = target
        }
    }

    public private(set) var entries: [Entry] = []
    public let capacity: Int

    public init(capacity: Int = 20) {
        self.capacity = max(1, capacity)
    }

    /// Translations arrive while the user types, so a result that extends or
    /// trims the newest entry replaces it instead of piling up "h", "he", "hel".
    public mutating func record(_ entry: Entry) {
        guard !entry.text.isEmpty, !entry.translation.isEmpty else { return }
        if let top = entries.first, top.target == entry.target,
            top.text.hasPrefix(entry.text) || entry.text.hasPrefix(top.text)
        {
            entries.removeFirst()
        }
        entries.removeAll { $0.text == entry.text && $0.target == entry.target }
        entries.insert(entry, at: 0)
        if entries.count > capacity { entries.removeLast(entries.count - capacity) }
    }

    public mutating func clear() {
        entries.removeAll()
    }
}
