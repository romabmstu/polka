import AppKit
import Observation
import OSLog
import PolkaCore
import PolkaSystem

/// System VPN services (through `scutil`) and proxy-based client apps such as
/// FSNT Client, shown and switched as one list. Only one stays on at a time.
@MainActor
@Observable
final class VPNModel {
    private(set) var connections: [VPNConnection] = []
    private(set) var busy: Set<String> = []
    private(set) var lastError: String?
    private(set) var hasLoaded = false
    /// When each tunnel was first seen connected, to show session length.
    private(set) var connectedSince: [String: Date] = [:]
    /// App-managed clients that are open, connected or not.
    private(set) var runningApps: Set<String> = []

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let controller = VPNController()
    @ObservationIgnored private let probe = NetworkProbe()
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var appLocations: [String: URL] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "Polka", category: "vpn")

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    var active: VPNConnection? {
        connections.first { $0.status == .connected } ?? connections.first { $0.status == .connecting }
    }

    /// Polls quickly while the panel is open and slowly otherwise, so the
    /// indicator in the notch stays roughly current at negligible cost.
    func startPolling(fast: Bool) {
        polling?.cancel()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: fast ? .seconds(2) : .seconds(15))
            }
        }
    }

    func refresh() async {
        var list: [VPNConnection] = []
        do {
            list = try await controller.connections()
        } catch {
            log.error("Listing VPN services failed: \(error.localizedDescription, privacy: .public)")
        }
        list += await appConnections(systemActive: list.contains { $0.status.isActive })

        let now = Date.now
        for connection in list {
            if connection.status == .connected {
                if connectedSince[connection.id] == nil { connectedSince[connection.id] = now }
            } else {
                connectedSince[connection.id] = nil
            }
        }
        connections = list
        hasLoaded = true
    }

    /// Connects `connection` and disconnects the others, or disconnects it if it
    /// is the active one.
    func toggle(_ connection: VPNConnection) async {
        await setActive(connection.status.isActive ? nil : connection.id)
    }

    func setActive(_ id: String?) async {
        let affected = Set(connections.filter(\.status.isActive).map(\.id)).union(id.map { [$0] } ?? [])
        busy.formUnion(affected)
        defer { busy.subtract(affected) }
        lastError = nil

        let system = connections.filter { !$0.isAppManaged }
        let targetApp = id.flatMap(VPNApp.bundleID(fromConnectionID:))
        do {
            // Turn everything else off first, so two clients never fight over routes.
            for connection in connections where connection.isAppManaged && connection.id != id {
                if let bundleID = VPNApp.bundleID(fromConnectionID: connection.id), isRunning(bundleID) {
                    await quit(bundleID)
                }
            }
            if let targetApp {
                try await controller.switchExclusively(to: nil, among: system)
                try await launch(targetApp)
            } else {
                try await controller.switchExclusively(to: id, among: system)
            }
        } catch {
            lastError = String(localized: "The VPN client did not respond. Open it to check its settings.")
            log.error("VPN switch failed: \(error.localizedDescription, privacy: .public)")
        }

        // Tunnels and proxy clients take a moment to come up.
        let attempts = targetApp == nil ? 6 : 14
        for _ in 0..<attempts {
            await refresh()
            if id == nil ? active == nil : connections.first(where: { $0.id == id })?.status == .connected { break }
            try? await Task.sleep(for: .milliseconds(700))
        }
        await explainAppState(target: targetApp, turnedOff: id == nil)
    }

    /// The app that owns a tunnel, found from its extension's bundle identifier
    /// (`com.vendor.app.tunnel` → `com.vendor.app`).
    func providerApp(for connection: VPNConnection) -> URL? {
        guard var id = connection.providerBundleID else { return nil }
        while !id.isEmpty {
            if let url = appURL(for: id) { return url }
            guard let dot = id.lastIndex(of: ".") else { break }
            id = String(id[..<dot])
            if id.split(separator: ".").count < 2 { break }
        }
        return nil
    }

    // MARK: App-managed clients

    /// Recognized clients that are installed, plus the ones the user added.
    var configuredApps: [VPNApp] {
        var result: [VPNApp] = []
        for entry in VPNApp.known {
            if let app = detect(names: entry.names, bundleIDs: entry.bundleIDs),
                !result.contains(where: { $0.bundleID == app.bundleID })
            {
                result.append(app)
            }
        }
        for app in preferences.vpnApps where !result.contains(where: { $0.bundleID == app.bundleID }) {
            result.append(app)
        }
        return result
    }

    func addApp(at url: URL) -> Bool {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, VPNApp.isValidBundleID(id),
            id != Bundle.main.bundleIdentifier
        else { return false }
        let name =
            (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        guard !preferences.vpnApps.contains(where: { $0.bundleID == id }) else { return true }
        preferences.vpnApps.append(VPNApp(bundleID: id, name: name))
        appLocations[id] = url
        Task { await refresh() }
        return true
    }

    func removeApp(_ bundleID: String) {
        preferences.vpnApps.removeAll { $0.bundleID == bundleID }
        Task { await refresh() }
    }

    func appURL(for bundleID: String) -> URL? {
        if let url = appLocations[bundleID] { return url }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        if let url { appLocations[bundleID] = url }
        return url
    }

    private func detect(names: [String], bundleIDs: [String]) -> VPNApp? {
        for id in bundleIDs {
            if let url = appURL(for: id) { return VPNApp(bundleID: id, name: displayName(of: url)) }
        }
        let folders = [URL(filePath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")]
        for name in names {
            for folder in folders {
                let url = folder.appending(path: name + ".app")
                if let id = Bundle(url: url)?.bundleIdentifier, VPNApp.isValidBundleID(id) {
                    appLocations[id] = url
                    return VPNApp(bundleID: id, name: name)
                }
            }
        }
        return nil
    }

    private func displayName(of url: URL) -> String {
        FileManager.default.displayName(atPath: url.path(percentEncoded: false)).replacingOccurrences(of: ".app", with: "")
    }

    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// A proxy client counts as connected while it runs and either the system
    /// proxy points at this Mac or the default route goes through a tunnel no
    /// system VPN accounts for.
    private func appConnections(systemActive: Bool) async -> [VPNConnection] {
        let apps = configuredApps
        guard !apps.isEmpty else {
            runningApps = []
            return []
        }
        let running = Set(apps.map(\.bundleID).filter { isRunning($0) })
        runningApps = running
        var routed = false
        if !running.isEmpty {
            let proxy = await probe.localProxyEnabled()
            let tunnel = NetworkRouting.isTunnel(await probe.defaultInterface())
            routed = proxy || (tunnel && !systemActive)
        }
        return apps.map { app in
            let status: VPNConnection.Status =
                running.contains(app.bundleID) ? (routed ? .connected : .disconnected) : .disconnected
            return VPNConnection(id: app.id, name: app.name, status: status, isEnabled: true, providerBundleID: app.bundleID)
        }
    }

    private func launch(_ bundleID: String) async throws {
        guard let url = appURL(for: bundleID) else { throw CocoaError(.fileNoSuchFile) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private func quit(_ bundleID: String) async {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        apps.forEach { $0.terminate() }
        for _ in 0..<20 where apps.contains(where: { !$0.isTerminated }) {
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    /// Proxy clients need their own "connect on launch" setting to come up by
    /// themselves, and a crashed one can leave the proxy pointing nowhere.
    private func explainAppState(target: String?, turnedOff: Bool) async {
        if let target, let app = connections.first(where: { $0.providerBundleID == target && $0.isAppManaged }),
            app.status != .connected, isRunning(target)
        {
            lastError = String(
                localized:
                    "\(app.name) is open but not connected. Turn on connecting at launch and the system proxy or TUN mode in its settings.")
        } else if turnedOff, runningApps.isEmpty, await probe.localProxyEnabled() {
            lastError = String(
                localized: "The system proxy still points to this Mac. Turn it off in System Settings › Network › Proxies.")
        }
    }
}
