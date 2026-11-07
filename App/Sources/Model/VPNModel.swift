import AppKit
import Observation
import OSLog
import PolkaCore
import PolkaSystem

/// System VPN services (through `scutil`), Tunnelblick configurations and
/// proxy-based client apps such as FSNT Client, shown as one list.
@MainActor
@Observable
final class VPNModel {
    private(set) var connections: [VPNConnection] = []
    private(set) var busy: Set<String> = []
    private(set) var lastError: String?
    private(set) var hasLoaded = false
    private(set) var systemStatusUnavailable = false
    /// When each tunnel was first seen connected, to show session length.
    private(set) var connectedSince: [String: Date] = [:]
    /// App-managed clients that are open, connected or not.
    private(set) var runningApps: Set<String> = []
    private(set) var throneConfigured = false
    private(set) var thronePort: UInt16 = 9095
    @ObservationIgnored private var throne: ThroneClient?

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let controller = VPNController()
    @ObservationIgnored private let tunnelblick = TunnelblickController()
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0
    private(set) var switching = false
    @ObservationIgnored private var appLocations: [String: URL] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "Polka", category: "vpn")

    init(preferences: Preferences) {
        self.preferences = preferences
        let savedPort = UserDefaults.standard.integer(forKey: "throneAPIPort")
        if let port = UInt16(exactly: savedPort), port > 0 { thronePort = port }
        if let key = try? ThroneKeychain.load(), let client = try? ThroneClient(keyText: key, port: thronePort) {
            throne = client
            throneConfigured = true
        }
    }

    var hasUnknownStatus: Bool { systemStatusUnavailable || connections.contains { $0.status == .unknown } }

    var activeConnections: [VPNConnection] { connections.filter { $0.status.isActive } }

    var active: VPNConnection? {
        connections.first { $0.status == .connected } ?? connections.first { $0.status == .connecting }
    }

    /// Polls quickly while the panel is open and slowly otherwise, so the
    /// indicator in the notch stays roughly current at negligible cost.
    func startPolling(fast: Bool) {
        polling?.cancel()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                if self?.switching == false { await self?.refresh() }
                try? await Task.sleep(for: fast ? .seconds(2) : .seconds(15))
            }
        }
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        var list: [VPNConnection] = []
        var systemFailed = false
        do {
            list = try await controller.connections()
        } catch {
            systemFailed = true
            log.error("Listing VPN services failed: \(error.localizedDescription, privacy: .public)")
            list = connections.filter(\.isSystemService).map {
                VPNConnection(id: $0.id, name: $0.name, status: .unknown, isEnabled: $0.isEnabled, providerBundleID: $0.providerBundleID)
            }
        }
        list += await tunnelblickConnections()
        list += await appConnections()

        guard generation == refreshGeneration, !Task.isCancelled else { return }
        systemStatusUnavailable = systemFailed
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

    func configureThrone(key: String, port: UInt16) async throws {
        guard port > 0 else { throw ThroneClient.Failure.connection }
        let client = try ThroneClient(keyText: key, port: port)
        _ = try await client.status()
        try ThroneKeychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
        throne = client
        thronePort = port
        UserDefaults.standard.set(Int(port), forKey: "throneAPIPort")
        throneConfigured = true
        await refresh()
    }

    func removeThrone() throws {
        try ThroneKeychain.remove()
        throne = nil
        throneConfigured = false
        Task { await refresh() }
    }

    func supportsThrone(_ connection: VPNConnection) -> Bool {
        connection.isAppManaged && connection.providerBundleID?.lowercased() == "moe.throne.macosx" && throneConfigured
    }

    /// Each switch changes only its own connection.
    func toggle(_ connection: VPNConnection) async {
        guard let current = connections.first(where: { $0.id == connection.id }) else { return }
        await change(current, connect: !current.status.isActive)
    }

    /// A scenario enables its selected VPN, or disconnects known active VPNs.
    @discardableResult
    func setActive(_ id: String?) async -> Bool {
        if let id {
            guard let connection = connections.first(where: { $0.id == id }) else { return false }
            if connection.status == .connected { return true }
            if connection.status != .disconnected {
                lastError = String(localized: "VPN status is unknown or changing. Check the VPN app.")
                return false
            }
            return await change(connection, connect: true)
        }
        var success = true
        for connection in activeConnections {
            if !(await change(connection, connect: false)) { success = false }
        }
        if hasUnknownStatus {
            lastError = String(localized: "Some VPN states are unknown. Check their apps.")
            success = false
        } else if !success {
            lastError = String(localized: "Some VPNs could not be disconnected. Check their apps.")
        }
        return success
    }

    @discardableResult
    private func change(_ connection: VPNConnection, connect: Bool) async -> Bool {
        guard !switching else { return false }
        switching = true
        defer { switching = false }
        busy.insert(connection.id)
        defer { busy.remove(connection.id) }
        lastError = nil
        do {
            if let bundleID = VPNApp.bundleID(fromConnectionID: connection.id) {
                if supportsThrone(connection), let throne {
                    if connect && !isRunning(bundleID) {
                        try await launch(bundleID)
                        var ready = false
                        for _ in 0..<20 {
                            if (try? await throne.status()) != nil { ready = true; break }
                            try await Task.sleep(for: .milliseconds(500))
                        }
                        guard ready else { throw ThroneClient.Failure.connection }
                    }
                    try await throne.setConnected(connect)
                } else {
                    if connect { try await launch(bundleID) }
                    lastError = String(localized: "Open the VPN app to control its connection.")
                }
            } else if let name = Tunnelblick.configurationName(fromConnectionID: connection.id) {
                if connect { try await tunnelblick.connect(name) } else { try await tunnelblick.disconnect(name) }
            } else if connection.isSystemService {
                if connect { try await controller.connect(connection.id) } else { try await controller.disconnect(connection.id) }
            }
        } catch TunnelblickController.Failure.notAuthorized {
            lastError = String(localized: "Allow Polka to control Tunnelblick in System Settings › Privacy & Security › Automation.")
            SystemSettings.open(.automation)
        } catch {
            lastError = String(localized: "The VPN client did not respond. Open it to check its settings.")
            log.error("VPN switch failed: \(error.localizedDescription, privacy: .public)")
        }
        guard lastError == nil else { return false }
        let attempts = connection.isTunnelblick ? 14 : 6
        for _ in 0..<attempts {
            await refresh()
            if let status = connections.first(where: { $0.id == connection.id })?.status,
                connect ? status == .connected : status == .disconnected { return true }
            try? await Task.sleep(for: .milliseconds(700))
        }
        lastError = String(localized: "VPN state did not change in time. Check the VPN app.")
        return false
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

    // MARK: Tunnelblick

    /// Asks Tunnelblick for live states while it runs; otherwise lists the
    /// installed configurations as off, without starting it.
    private func tunnelblickConnections() async -> [VPNConnection] {
        guard appURL(for: Tunnelblick.bundleID) != nil else { return [] }
        if isRunning(Tunnelblick.bundleID) {
            do {
                return try await tunnelblick.connections()
            } catch {
                log.error("Reading Tunnelblick failed: \(error.localizedDescription, privacy: .public)")
                return TunnelblickController.installedConfigurationNames().map {
                    Tunnelblick.connection(named: $0, status: .unknown)
                }
            }
        }
        return TunnelblickController.installedConfigurationNames().map {
            Tunnelblick.connection(named: $0, status: .disconnected)
        }
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
        // Tunnelblick has its own, richer integration.
        for app in preferences.vpnApps
        where app.bundleID != Tunnelblick.bundleID && !result.contains(where: { $0.bundleID == app.bundleID }) {
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

    /// Only the client's authenticated API establishes its connection state.
    private func appConnections() async -> [VPNConnection] {
        let apps = configuredApps
        let running = Set(apps.map(\.bundleID).filter { isRunning($0) })
        runningApps = running
        var list: [VPNConnection] = []
        for app in apps {
            var status: VPNConnection.Status = .unknown
            if app.bundleID.lowercased() == "moe.throne.macosx", let throne {
                status = (try? await throne.status()) ?? .unknown
            }
            list.append(VPNConnection(id: app.id, name: app.name, status: status, isEnabled: true, providerBundleID: app.bundleID))
        }
        return list
    }

    private func launch(_ bundleID: String) async throws {
        guard let url = appURL(for: bundleID) else { throw CocoaError(.fileNoSuchFile) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

}
