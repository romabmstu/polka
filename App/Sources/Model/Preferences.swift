import Foundation
import Observation
import PolkaCore

enum PanelSection: String, CaseIterable, Codable, Identifiable {
    case overview, tabs, vpn, media, calendar, calculator, clipboard, shelf

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .overview: "Overview"
        case .tabs: "Tabs"
        case .vpn: "VPN"
        case .media: "Music"
        case .calendar: "Calendar"
        case .calculator: "Calculator"
        case .clipboard: "Clipboard"
        case .shelf: "Files"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .tabs: "square.on.square"
        case .vpn: "lock.shield"
        case .media: "music.note"
        case .calendar: "calendar"
        case .calculator: "plus.forwardslash.minus"
        case .clipboard: "doc.on.clipboard"
        case .shelf: "tray.and.arrow.down"
        }
    }
}

enum DisplayChoice: String, CaseIterable, Codable {
    /// The built-in display if there is one (it has the notch), otherwise the main display.
    case builtIn
    case main
}

/// User settings backed by `UserDefaults`. Every property writes through on change.
@MainActor
@Observable
final class Preferences {
    private let defaults: UserDefaults

    var openOnHover: Bool { didSet { defaults.set(openOnHover, forKey: Key.openOnHover) } }
    var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: Key.hoverDelay) } }
    var display: DisplayChoice { didSet { defaults.set(display.rawValue, forKey: Key.display) } }
    var sections: [PanelSection] { didSet { store(sections, Key.sections) } }
    var clipboardHistoryEnabled: Bool { didSet { defaults.set(clipboardHistoryEnabled, forKey: Key.clipboard) } }
    var exchangeRatesEnabled: Bool { didSet { defaults.set(exchangeRatesEnabled, forKey: Key.rates) } }
    var favoriteCurrencies: [String] { didSet { store(favoriteCurrencies, Key.currencies) } }
    var playerBundleID: String { didSet { defaults.set(playerBundleID, forKey: Key.player) } }
    var scenarios: [Scenario] { didSet { store(scenarios, Key.scenarios) } }
    var hasSeenWelcome: Bool { didSet { defaults.set(hasSeenWelcome, forKey: Key.welcome) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        openOnHover = defaults.object(forKey: Key.openOnHover) as? Bool ?? true
        hoverDelay = defaults.object(forKey: Key.hoverDelay) as? Double ?? 0.12
        display = defaults.string(forKey: Key.display).flatMap { DisplayChoice(rawValue: $0) } ?? .builtIn
        sections = Self.load([PanelSection].self, Key.sections, defaults) ?? PanelSection.allCases
        clipboardHistoryEnabled = defaults.object(forKey: Key.clipboard) as? Bool ?? true
        exchangeRatesEnabled = defaults.bool(forKey: Key.rates)
        favoriteCurrencies = Self.load([String].self, Key.currencies, defaults) ?? Self.defaultCurrencies()
        playerBundleID = defaults.string(forKey: Key.player) ?? ""
        scenarios = Self.load([Scenario].self, Key.scenarios, defaults) ?? []
        hasSeenWelcome = defaults.bool(forKey: Key.welcome)
    }

    func isEnabled(_ section: PanelSection) -> Bool { sections.contains(section) }

    func setEnabled(_ section: PanelSection, _ enabled: Bool) {
        if enabled, !sections.contains(section) {
            sections = PanelSection.allCases.filter { $0 == section || sections.contains($0) }
        } else if !enabled, section != .overview {
            sections.removeAll { $0 == section }
        }
    }

    private func store<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func defaultCurrencies() -> [String] {
        var codes = [Locale.current.currency?.identifier ?? "USD", "USD", "EUR", "GBP", "CNY"]
        var seen = Set<String>()
        codes = codes.filter { seen.insert($0).inserted }
        return Array(codes.prefix(4))
    }

    private enum Key {
        static let openOnHover = "openOnHover"
        static let hoverDelay = "hoverDelay"
        static let display = "display"
        static let sections = "sections"
        static let clipboard = "clipboardHistoryEnabled"
        static let rates = "exchangeRatesEnabled"
        static let currencies = "favoriteCurrencies"
        static let player = "playerBundleID"
        static let scenarios = "scenarios"
        static let welcome = "hasSeenWelcome"
    }
}
