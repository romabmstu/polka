import Foundation
import PolkaCore

/// Lists and toggles VPN configurations through `scutil`, the same interface
/// System Settings uses. Works for any client that registers its tunnel with
/// the system; it needs no privileges.
public struct VPNController: Sendable {
    public enum Failure: Error, Equatable {
        case invalidServiceID
    }

    private static let scutil = "/usr/sbin/scutil"
    private let runner: CommandRunner

    public init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    public func connections() async throws -> [VPNConnection] {
        let result = try await runner.runChecked(Self.scutil, ["--nc", "list"], timeout: .seconds(5))
        return SCUtilParser.connections(from: result.output)
    }

    public func status(of serviceID: String) async throws -> VPNConnection.Status {
        guard SCUtilParser.isValidServiceID(serviceID) else { throw Failure.invalidServiceID }
        let result = try await runner.runChecked(Self.scutil, ["--nc", "status", serviceID], timeout: .seconds(5))
        return SCUtilParser.status(from: result.output)
    }

    public func connect(_ serviceID: String) async throws {
        guard SCUtilParser.isValidServiceID(serviceID) else { throw Failure.invalidServiceID }
        try await runner.runChecked(Self.scutil, ["--nc", "start", serviceID], timeout: .seconds(10))
    }

    public func disconnect(_ serviceID: String) async throws {
        guard SCUtilParser.isValidServiceID(serviceID) else { throw Failure.invalidServiceID }
        try await runner.runChecked(Self.scutil, ["--nc", "stop", serviceID], timeout: .seconds(10))
    }

    /// Connects `serviceID` and disconnects every other active tunnel, because
    /// two clients fighting over routes is never what the user wants.
    public func switchExclusively(to serviceID: String?, among connections: [VPNConnection]) async throws {
        for connection in connections where connection.status.isActive && connection.id != serviceID {
            try await disconnect(connection.id)
        }
        if let serviceID {
            try await connect(serviceID)
        }
    }
}
