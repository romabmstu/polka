import Foundation
import Testing

@testable import PolkaCore

@Suite struct TranslationRouteTests {
    @Test func translatesIntoTheOtherLanguage() {
        #expect(TranslationRoute.target(detected: "ru", primary: "ru", secondary: "en") == "en")
        #expect(TranslationRoute.target(detected: "en", primary: "ru", secondary: "en") == "ru")
        #expect(TranslationRoute.target(detected: "de", primary: "ru", secondary: "en") == "ru")
        #expect(TranslationRoute.target(detected: "pt-BR", primary: "pt", secondary: "en") == "en")
        #expect(TranslationRoute.target(detected: nil, primary: "ru", secondary: "en") == "en")
    }

    @Test func preparesInput() {
        #expect(TranslationRoute.prepare("  \n ") == nil)
        #expect(TranslationRoute.prepare("  hello \n") == "hello")
        #expect(TranslationRoute.prepare(String(repeating: "a", count: 6_000))?.count == TranslationRoute.maximumLength)
        #expect(TranslationRoute.baseCode("zh_Hans") == "zh")
    }
}

@Suite struct TranslationHistoryTests {
    @Test func collapsesTypingIntoOneEntry() {
        var history = TranslationHistory(capacity: 3)
        for text in ["h", "he", "hello"] {
            history.record(.init(text: text, translation: text.uppercased(), source: "en", target: "ru"))
        }
        #expect(history.entries.map(\.text) == ["hello"])

        history.record(.init(text: "world", translation: "мир", source: "en", target: "ru"))
        history.record(.init(text: "hello", translation: "привет", source: "en", target: "ru"))
        #expect(history.entries.map(\.text) == ["hello", "world"])

        for word in ["a1", "b2", "c3"] {
            history.record(.init(text: word, translation: word, source: "en", target: "ru"))
        }
        #expect(history.entries.count == 3)
        history.record(.init(text: "x", translation: "", source: "en", target: "ru"))
        #expect(history.entries.first?.text == "c3")
    }
}
