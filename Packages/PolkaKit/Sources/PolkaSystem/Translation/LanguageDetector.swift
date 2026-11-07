import Foundation
import NaturalLanguage

/// Guesses the language of a piece of text on device. The user's two
/// languages get a head start, which matters for short words that look the
/// same in several languages.
public enum LanguageDetector {
    public static func dominantLanguage(of text: String, preferring hints: [String]) -> String? {
        let recognizer = NLLanguageRecognizer()
        if !hints.isEmpty {
            var weights: [NLLanguage: Double] = [:]
            for hint in hints { weights[NLLanguage(rawValue: hint)] = 0.8 / Double(hints.count) }
            recognizer.languageHints = weights
        }
        recognizer.processString(String(text.prefix(1_000)))
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return language.rawValue
    }
}
