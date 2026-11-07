import Foundation

/// A VPN client that does not register its tunnel with the system, so
/// `scutil` cannot see it: proxy-based clients such as FSNT Client (built on
/// sing-box). Polka turns these on by launching the app and off by quitting it,
/// and reads their state from the network settings.
public struct VPNApp: Identifiable, Hashable, Codable, Sendable {
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    /// Shares the ID space with system services, which are UUIDs, so a
    /// scenario can refer to either.
    public var id: String { Self.idPrefix + bundleID }

    public static let idPrefix = "app:"

    public static func bundleID(fromConnectionID id: String) -> String? {
        guard id.hasPrefix(idPrefix) else { return nil }
        let bundleID = String(id.dropFirst(idPrefix.count))
        return isValidBundleID(bundleID) ? bundleID : nil
    }

    public static func isValidBundleID(_ id: String) -> Bool {
        Scenario.isValidBundleID(id)
    }

    /// Clients Polka looks for without being told. Matched by bundle
    /// identifier first, then by the app's name in the Applications folder,
    /// because rebranded builds keep the name but not always the identifier.
    public static let known: [(names: [String], bundleIDs: [String])] = [
        (names: ["FSNT Client", "FSNT"], bundleIDs: ["moe.Throne.macosx", "moe.throne.macosx"]),
        (names: ["Throne"], bundleIDs: []),
    ]
}

extension VPNConnection {
    /// Whether this entry is an app Polka launches and quits rather than a
    /// service in System Settings › VPN.
    public var isAppManaged: Bool { id.hasPrefix(VPNApp.idPrefix) }
}

/// Reads what proxy-based clients change in the network settings.
public enum NetworkRouting {
    /// Parses `scutil --proxy`. True when an HTTP, HTTPS or SOCKS system proxy
    /// is switched on and points at this Mac — the mark of a local client.
    public static func localProxyEnabled(scutilProxyOutput output: String) -> Bool {
        var values: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            values[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        let local: Set<String> = ["127.0.0.1", "localhost", "::1"]
        for kind in ["HTTP", "HTTPS", "SOCKS"] where values[kind + "Enable"] == "1" {
            if let host = values[kind + "Proxy"], local.contains(host.lowercased()) { return true }
        }
        return false
    }

    /// Parses `route -n get default` and returns the interface name.
    public static func defaultInterface(routeOutput output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "interface" {
                let name = parts[1].trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? nil : name
            }
        }
        return nil
    }

    /// Tunnel-mode clients route all traffic through a `utun` interface.
    public static func isTunnel(_ interface: String?) -> Bool {
        interface?.hasPrefix("utun") ?? false
    }
}
