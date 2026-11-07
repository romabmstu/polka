import Foundation

/// A VPN configuration registered with the system (System Settings › VPN),
/// as reported by `scutil --nc list`.
public struct VPNConnection: Identifiable, Hashable, Sendable {
    public enum Status: String, Sendable {
        case connected, connecting, disconnecting, disconnected, invalid, unknown

        init(scutilValue: String) {
            switch scutilValue.lowercased() {
            case "connected": self = .connected
            case "connecting": self = .connecting
            case "disconnecting": self = .disconnecting
            case "disconnected": self = .disconnected
            case "invalid": self = .invalid
            default: self = .unknown
            }
        }

        public var isActive: Bool { self == .connected || self == .connecting }
    }

    /// Service ID — a UUID string assigned by the system.
    public let id: String
    public let name: String
    public let status: Status
    public let isEnabled: Bool
    /// Bundle identifier of the app that provides the tunnel, when the
    /// configuration comes from a Network Extension (`com.wireguard.macos`, …).
    public let providerBundleID: String?

    public init(id: String, name: String, status: Status, isEnabled: Bool, providerBundleID: String?) {
        self.id = id
        self.name = name
        self.status = status
        self.isEnabled = isEnabled
        self.providerBundleID = providerBundleID
    }
}

public enum SCUtilParser {
    /// Parses the output of `scutil --nc list`. Lines that do not look like a
    /// service are skipped rather than guessed at.
    public static func connections(from output: String) -> [VPNConnection] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            guard let match = line.wholeMatch(of: serviceLine) else { return nil }
            let kind = String(match.output.kind)
            var provider = kind.firstMatch(of: parenthesized).map { String($0.output.value) }
            if provider == nil, let proto = match.output.proto, let colon = proto.firstIndex(of: ":") {
                let tail = proto[proto.index(after: colon)...]
                if tail.contains(".") { provider = String(tail) }
            }
            return VPNConnection(
                id: String(match.output.id),
                name: String(match.output.name),
                status: .init(scutilValue: String(match.output.status)),
                isEnabled: match.output.enabled != nil,
                providerBundleID: provider
            )
        }
    }

    /// Parses `scutil --nc status <id>`; the first line is the status word.
    public static func status(from output: String) -> VPNConnection.Status {
        let first = output.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return .init(scutilValue: first.trimmingCharacters(in: .whitespaces))
    }

    /// Service IDs go straight into a process argument list; make sure they are
    /// what the system produces and nothing else.
    public static func isValidServiceID(_ id: String) -> Bool {
        id.wholeMatch(of: serviceID) != nil
    }

    nonisolated(unsafe) private static let serviceLine =
        /\s*(?<enabled>\*)?\s*\((?<status>[^)]+)\)\s+(?<id>[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\s+(?<kind>.+?)\s+"(?<name>[^"]*)"\s*(?:\[(?<proto>[^\]]*)\])?\s*/
    nonisolated(unsafe) private static let parenthesized = /\((?<value>[A-Za-z0-9.\-]+\.[A-Za-z0-9.\-]+)\)/
    nonisolated(unsafe) private static let serviceID =
        /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/
}
