import AppKit
import Observation
import OSLog
import PolkaCore
import PolkaSystem

@MainActor
@Observable
final class VPNModel {
    private(set) var connections: [VPNConnection] = []
    private(set) var busy: Set<String> = []
    private(set) var lastError: String?
    private(set) var hasLoaded = false
    /// When each tunnel was first seen connected, to show session length.
    private(set) var connectedSince: [String: Date] = [:]

    @ObservationIgnored private let controller = VPNController()
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "Polka", category: "vpn")

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
        do {
            let list = try await controller.connections()
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
        } catch {
            log.error("Listing VPN services failed: \(error.localizedDescription, privacy: .public)")
            hasLoaded = true
        }
    }

    /// Connects `connection` and disconnects the others, or disconnects it if it
    /// is the active one.
    func toggle(_ connection: VPNConnection) async {
        await setActive(connection.status.isActive ? nil : connection.id)
    }

    func setActive(_ serviceID: String?) async {
        let affected = Set(connections.filter(\.status.isActive).map(\.id)).union(serviceID.map { [$0] } ?? [])
        busy.formUnion(affected)
        defer { busy.subtract(affected) }
        lastError = nil
        do {
            try await controller.switchExclusively(to: serviceID, among: connections)
        } catch {
            lastError = String(localized: "The VPN client did not respond. Open it to check its settings.")
            log.error("VPN switch failed: \(error.localizedDescription, privacy: .public)")
        }
        // Tunnels take a moment to come up; poll a few times for a fresh status.
        for _ in 0..<6 {
            await refresh()
            if serviceID == nil ? active == nil : connections.first(where: { $0.id == serviceID })?.status == .connected {
                break
            }
            try? await Task.sleep(for: .milliseconds(700))
        }
    }

    /// The app that owns a tunnel, found from its extension's bundle identifier
    /// (`com.vendor.app.tunnel` → `com.vendor.app`).
    func providerApp(for connection: VPNConnection) -> URL? {
        guard var id = connection.providerBundleID else { return nil }
        while !id.isEmpty {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url }
            guard let dot = id.lastIndex(of: ".") else { break }
            id = String(id[..<dot])
            if id.split(separator: ".").count < 2 { break }
        }
        return nil
    }
}
