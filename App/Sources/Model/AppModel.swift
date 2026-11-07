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
    let vpn: VPNModel
    let media = MediaModel()
    let agenda: AgendaModel
    let calculator: CalculatorModel
    let clipboard = ClipboardModel()
    let shelf = ShelfModel()
    let updates = UpdateModel()

    private(set) var runningScenarioID: Scenario.ID?

    @ObservationIgnored var openSettings: () -> Void = {}
    @ObservationIgnored private let shortcuts = ShortcutsRunner()
    @ObservationIgnored private let system = SystemControls()
    @ObservationIgnored private let log = Logger(subsystem: "Polka", category: "app")

    init() {
        let preferences = Preferences()
        self.preferences = preferences
        agenda = AgendaModel(preferences: preferences)
        vpn = VPNModel(preferences: preferences)
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

    /// ⌥⇧S: save the tab open in the frontmost browser, asking where unless
    /// the user turned that off.
    func saveFromBrowser() {
        Task {
            guard let request = await tabs.captureFrontWindow() else {
                flashBrowserProblem()
                return
            }
            if preferences.askWhereToSave {
                panel.presentSavePicker(request)
            } else {
                save(request.current, to: tabs.library.lastUsedGroupID ?? tabs.library.defaultGroupID)
            }
        }
    }

    /// Pages handed over by the Services menu. Without links in the selection,
    /// the page the selection came from is saved instead.
    func saveFromService(_ pages: [PageReference], sourceApp: String?) {
        if pages.isEmpty {
            saveFromBrowser()
            return
        }
        Task {
            var pages = pages
            // A single link is often the page itself: borrow the tab's title.
            if pages.count == 1, pages[0].title.isEmpty,
                let current = await tabs.refreshCurrentPage(),
                URLNormalizer.identity(of: current.url) == URLNormalizer.identity(of: pages[0].url)
            {
                pages[0] = current
            }
            panel.presentSavePicker(SaveRequest(source: sourceApp ?? "Polka", current: pages))
        }
    }

    func save(_ pages: [PageReference], to groupID: UUID) {
        let result = tabs.add(pages, to: groupID)
        let groupName = tabs.library.group(groupID)?.name ?? ""
        panel.collapse()
        if result.added.isEmpty {
            panel.flash(.init(symbol: "checkmark", text: String(localized: "Already in “\(groupName)”")))
        } else if result.added.count == 1 {
            panel.flash(.init(symbol: "checkmark", text: String(localized: "Saved to “\(groupName)”")))
        } else {
            panel.flash(.init(symbol: "checkmark", text: String(localized: "\(result.added.count) tabs saved to “\(groupName)”")))
        }
    }

    private func flashBrowserProblem() {
        switch tabs.browserState {
        case .notAuthorized(let browser):
            panel.flash(.init(symbol: "hand.raised", text: String(localized: "Allow Polka to control \(browser.name)")))
            SystemSettings.open(.automation)
        case .noBrowser:
            panel.flash(.init(symbol: "exclamationmark.triangle", text: String(localized: "No browser is open")))
        default:
            panel.flash(.init(symbol: "exclamationmark.triangle", text: String(localized: "No tab to save")))
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
        case .openApp(let bundleID):
            guard Scenario.isValidBundleID(bundleID),
                let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            else { throw CocoaError(.fileNoSuchFile) }
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case .quitApp(let bundleID):
            guard Scenario.isValidBundleID(bundleID), bundleID != Bundle.main.bundleIdentifier else { return }
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
        case .appearance(let appearance):
            do {
                try await system.setAppearance(appearance)
            } catch SystemControls.Failure.notAuthorized {
                SystemSettings.open(.automation)
                throw SystemControls.Failure.notAuthorized
            }
        case .volume(let percent):
            try await system.setVolume(percent: percent)
        case .mute(let muted):
            try await system.setMuted(muted)
        }
    }

    func availableShortcuts() async -> [String] {
        (try? await shortcuts.names()) ?? []
    }
}
