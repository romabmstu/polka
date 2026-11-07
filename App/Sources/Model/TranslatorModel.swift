import AppKit
import Observation
import PolkaCore
import PolkaSystem

/// State of the Translator section. The translation itself runs in the view
/// (Apple's Translation framework hands out sessions only to SwiftUI); this
/// model decides what to translate and keeps the result and history.
@MainActor
@Observable
final class TranslatorModel {
    static let shared = TranslatorModel()

    struct Request: Equatable, Sendable {
        let id = UUID()
        let text: String
        /// Nil lets the framework detect the language itself.
        let source: String?
        let target: String
    }

    var input = "" {
        didSet { if TranslationRoute.prepare(input) == nil { reset() } }
    }
    var primary: String { didSet { defaults.set(primary, forKey: Key.primary) } }
    var secondary: String { didSet { defaults.set(secondary, forKey: Key.secondary) } }

    private(set) var output = ""
    private(set) var detected: String?
    private(set) var target: String?
    private(set) var isWorking = false
    private(set) var errorText: String?
    private(set) var needsLanguageDownload = false
    private var retryCount = 0
    private(set) var history = TranslationHistory()
    private(set) var supportedLanguages: [String] = []
    /// Bumped to move keyboard focus into the input field.
    private(set) var focusRequest = 0

    @ObservationIgnored private(set) var pending: Request?
    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let primary = "translatorPrimaryLanguage"
        static let secondary = "translatorSecondaryLanguage"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let system = TranslationRoute.baseCode(Locale.preferredLanguages.first ?? "en")
        primary = defaults.string(forKey: Key.primary) ?? system
        secondary = defaults.string(forKey: Key.secondary) ?? (system == "en" ? "es" : "en")
    }

    /// Changes whenever a new translation is due.
    var requestKey: String { "\(primary)|\(secondary)|\(input)|\(retryCount)" }

    func makeRequest() -> Request? {
        guard let text = TranslationRoute.prepare(input) else { return nil }
        let language = LanguageDetector.dominantLanguage(of: text, preferring: [primary, secondary])
        let target = TranslationRoute.target(detected: language, primary: primary, secondary: secondary)
        let request = Request(text: text, source: language.map(TranslationRoute.baseCode), target: target)
        pending = request
        detected = request.source
        self.target = target
        isWorking = true
        errorText = nil
        needsLanguageDownload = false
        return request
    }

    func finish(_ request: Request, translation: String) {
        guard request == pending else { return }
        output = translation
        isWorking = false
        history.record(.init(text: request.text, translation: translation, source: request.source, target: request.target))
    }

    func fail(_ request: Request, message: String, needsDownload: Bool = false) {
        guard request == pending else { return }
        isWorking = false
        output = ""
        errorText = message
        needsLanguageDownload = needsDownload
    }

    func setSupportedLanguages(_ codes: [String]) {
        supportedLanguages = codes
    }

    /// Opens with text from a selection, the Services menu or history.
    func load(_ text: String?) {
        if let text, let prepared = TranslationRoute.prepare(text) { input = prepared }
        focusRequest += 1
    }

    /// Translate the result back: it becomes the new input.
    func reverse() {
        guard !output.isEmpty else { return }
        input = output
    }

    func swapLanguages() {
        (primary, secondary) = (secondary, primary)
    }

    func copyOutput() {
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
    }

    func clear() {
        input = ""
        focusRequest += 1
    }

    func retry() { retryCount += 1 }

    func clearHistory() {
        history.clear()
    }

    private func reset() {
        pending = nil
        output = ""
        detected = nil
        target = nil
        isWorking = false
        errorText = nil
        needsLanguageDownload = false
    }

    static func displayName(of code: String) -> String {
        let name = Locale.current.localizedString(forLanguageCode: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
