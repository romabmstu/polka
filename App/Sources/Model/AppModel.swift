import AppKit
import Observation
import OSLog
import PolkaCore
import PolkaSystem

/// Composition root: owns every feature model and the panel state.
@MainActor
@Observable
final class AppModel {
    let preferences: Preferences
    let panel = PanelState()
    let tabs = TabsModel()
    let vpn = VPNModel()
    let media = MediaModel()
    let agenda: AgendaModel
    let calculator: CalculatorModel
    let clipboard = ClipboardModel()
    let shelf = ShelfModel()
    let updates = UpdateModel()

    private(set) var runningScenarioID: Scenario.ID?

    @ObservationIgnored var openSettings: () -> Void = {}
    @ObservationIgnored private let shortcuts = ShortcutsRunner()
    @ObservationIgnored private let log = Logger(subsystem: "Polka", category: "app")

    init() {
        let preferences = Preferences()
        self.preferences = preferences
        agenda = AgendaModel(preferences: preferences)
        calculator = CalculatorModel(defaultCurrency: preferences.favoriteCurrencies.first ?? "USD")
    }

    func start() {
        Task { await tabs.load() }
        vpn.startPolling(fast: false)
        media.start()
        agenda.start()
        clipboard.setEnabled(preferences.clipboardHistoryEnabled)
        updates.onNewUpdate = { [weak self] manifest in
            self?.panel.flash(.init(symbol: "arrow.down.circle", text: String(localized: "Polka \(manifest.version) is available")))
        }
        updates.startAutomaticChecks(preferences: preferences)
        if !preferences.hasSeenWelcome {
            panel.section = .overview
            panel.expand(pinned: true)
        }
    }

    /// Called whenever the panel opens, so what it shows is fresh.
    func panelDidExpand() {
        vpn.startPolling(fast: true)
        agenda.reload()
        Task { await tabs.refreshCurrentPage() }
        Task { await calculator.refreshRatesIfNeeded(enabled: preferences.exchangeRatesEnabled) }
    }

    func panelDidCollapse() {
        vpn.startPolling(fast: false)
        if !preferences.hasSeenWelcome { preferences.hasSeenWelcome = true }
    }

    // MARK: Actions that span features

    func saveCurrentSafariTab(to groupID: UUID? = nil) {
        Task {
            await tabs.refreshCurrentPage()
            guard let page = tabs.currentPage else {
                panel.flash(.init(symbol: "exclamationmark.triangle", text: String(localized: "No Safari tab to save")))
                return
            }
            let target = groupID ?? tabs.library.defaultGroupID
            let result = tabs.add([page], to: target)
            let groupName = tabs.library.group(target)?.name ?? ""
            if result.added.isEmpty {
                panel.flash(.init(symbol: "checkmark", text: String(localized: "Already in “\(groupName)”")))
            } else {
                panel.flash(.init(symbol: "checkmark", text: String(localized: "Saved to “\(groupName)”"), canUndo: false))
            }
        }
    }

    func run(_ scenario: Scenario) {
        guard runningScenarioID == nil else { return }
        runningScenarioID = scenario.id
        Task {
            defer { runningScenarioID = nil }
            var failures = 0
            for action in scenario.actions {
                do { try await perform(action) } catch {
                    failures += 1
                    log.error("Scenario step failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            let text =
                failures == 0
                ? String(localized: "“\(scenario.name)” is on")
                : String(localized: "“\(scenario.name)”: some steps failed")
            panel.flash(.init(symbol: failures == 0 ? scenario.symbol : "exclamationmark.triangle", text: text))
        }
    }

    private func perform(_ action: Scenario.Action) async throws {
        switch action {
        case .vpn(let serviceID):
            if vpn.connections.isEmpty { await vpn.refresh() }
            await vpn.setActive(serviceID)
        case .media(.play):
            media.play()
        case .media(.pause):
            media.pause()
        case .openTabGroup(let id):
            if let group = tabs.library.group(id) { await tabs.openGroup(group, inNewWindow: false) }
        case .runShortcut(let name):
            try await shortcuts.run(name)
        case .openURL(let url):
            if URLNormalizer.isSavable(url) { NSWorkspace.shared.open(url) }
        }
    }

    func availableShortcuts() async -> [String] {
        (try? await shortcuts.names()) ?? []
    }
}
