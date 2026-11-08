import AppKit
import ApplicationServices
import EventKit
import Observation
import PolkaSystem
import ServiceManagement

/// Live status of everything Polka can ask the system for, for the welcome
/// window and bug reports. Reading a status never shows a prompt.
@MainActor
@Observable
final class PermissionsModel {
    enum State: Equatable {
        case granted, denied, notAsked
        /// The browser has to be running for macOS to answer.
        case needsApp
        case unknown
    }

    struct BrowserStatus: Identifiable, Equatable {
        let browser: Browser
        let appURL: URL
        var state: State
        var id: String { browser.rawValue }
    }

    private(set) var browsers: [BrowserStatus] = []
    private(set) var calendars: State = .unknown
    private(set) var accessibility = false
    private(set) var launchAtLogin = false
    private(set) var launchAtLoginError: String?
    private(set) var busy: Set<String> = []

    func refresh() {
        browsers = Browser.allCases.compactMap { browser in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier) else {
                return nil
            }
            return BrowserStatus(browser: browser, appURL: url, state: Self.state(AutomationPermission.state(of: browser.bundleIdentifier)))
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: calendars = .granted
        case .notDetermined: calendars = .notAsked
        case .denied, .restricted, .writeOnly: calendars = .denied
        @unknown default: calendars = .unknown
        }
        accessibility = AXIsProcessTrusted()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Shows the macOS prompt for this browser, starting the browser first
    /// if needed, or opens System Settings if the user already said no.
    func request(_ status: BrowserStatus) async {
        let id = status.browser.bundleIdentifier
        switch status.state {
        case .denied:
            SystemSettings.open(.automation)
            return
        case .granted:
            return
        default:
            break
        }
        busy.insert(id)
        defer {
            busy.remove(id)
            refresh()
        }
        if !status.browser.isRunning {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            _ = try? await NSWorkspace.shared.openApplication(at: status.appURL, configuration: configuration)
            // Give the browser a moment to start answering Apple Events.
            for _ in 0..<20 where AutomationPermission.state(of: id) == .appNotRunning {
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        _ = await AutomationPermission.request(id)
    }

    func requestCalendars(using agenda: AgendaModel) async {
        if calendars == .denied {
            SystemSettings.open(.calendars)
            return
        }
        await agenda.requestAccess()
        refresh()
    }

    func requestAccessibility() {
        // The prompt points to the right pane; open it as well in case the
        // prompt was dismissed before.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        SystemSettings.open(.accessibility)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refresh()
    }

    /// One line per permission, for bug reports.
    var summary: String {
        func word(_ state: State) -> String {
            switch state {
            case .granted: "allowed"
            case .denied: "denied"
            case .notAsked: "not asked"
            case .needsApp: "app not running"
            case .unknown: "unknown"
            }
        }
        let browserList = browsers.isEmpty
            ? "none installed"
            : browsers.map { "\($0.browser.name) \(word($0.state))" }.joined(separator: ", ")
        return [
            "Browsers: \(browserList)",
            "Calendars: \(word(calendars))",
            "Accessibility: \(accessibility ? "allowed" : "not allowed")",
            "Open at login: \(launchAtLogin ? "on" : "off")",
        ].joined(separator: "\n")
    }

    private static func state(_ state: AutomationPermission.State) -> State {
        switch state {
        case .granted: .granted
        case .denied: .denied
        case .notAsked: .notAsked
        case .appNotRunning: .needsApp
        case .unknown: .unknown
        }
    }
}
