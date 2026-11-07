import Foundation

/// Tunnelblick (OpenVPN) keeps its tunnels to itself, so `scutil` cannot see
/// them, but it has a scripting dictionary. Each configuration becomes one
/// entry in the VPN list.
public enum Tunnelblick {
    public static let bundleID = "net.tunnelblick.tunnelblick"
    public static let idPrefix = "tunnelblick:"

    public static func connectionID(for name: String) -> String {
        idPrefix + name
    }

    public static func configurationName(fromConnectionID id: String) -> String? {
        guard id.hasPrefix(idPrefix) else { return nil }
        let name = String(id.dropFirst(idPrefix.count))
        return isValidConfigurationName(name) ? name : nil
    }

    /// Names reach the script only as `argv`; still keep them to what
    /// Tunnelblick itself allows in a file name.
    public static func isValidConfigurationName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 200 && !name.hasPrefix("-")
            && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || $0 == "/" }
    }

    /// Tunnelblick reports OpenVPN's states; anything between "off" and
    /// "connected" is shown as connecting.
    public static func status(fromState state: String) -> VPNConnection.Status {
        switch state.trimmingCharacters(in: .whitespaces).uppercased() {
        case "CONNECTED": .connected
        case "EXITING", "", "SLEEP", "DISCONNECTED": .disconnected
        case "DISCONNECTING": .disconnecting
        default: .connecting
        }
    }

    /// Parses `name␟state␞` records produced by Polka's listing script.
    public static func connections(fromScriptOutput output: String) -> [VPNConnection] {
        output.split(separator: "\u{1E}").compactMap { record in
            let fields = record.split(separator: "\u{1F}", omittingEmptySubsequences: false)
            guard fields.count == 2 else { return nil }
            let name = String(fields[0]).trimmingCharacters(in: .newlines)
            guard isValidConfigurationName(name) else { return nil }
            return connection(named: name, status: status(fromState: String(fields[1])))
        }
    }

    /// Configuration names from the contents of Tunnelblick's folders, used
    /// while the app is not running (asking it would launch it).
    public static func configurationNames(fromFileNames names: [String]) -> [String] {
        var seen = Set<String>()
        return names.compactMap { file -> String? in
            guard file.hasSuffix(".tblk") else { return nil }
            let name = String(file.dropLast(".tblk".count))
            guard isValidConfigurationName(name), seen.insert(name).inserted else { return nil }
            return name
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public static func connection(named name: String, status: VPNConnection.Status) -> VPNConnection {
        VPNConnection(id: connectionID(for: name), name: name, status: status, isEnabled: true, providerBundleID: bundleID)
    }
}

extension VPNConnection {
    public var isTunnelblick: Bool { id.hasPrefix(Tunnelblick.idPrefix) }
    /// Registered in System Settings › VPN and switched with `scutil`.
    public var isSystemService: Bool { !isAppManaged && !isTunnelblick }
}
