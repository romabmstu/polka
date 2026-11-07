import Foundation
import PolkaCore

/// Looks at the system proxy and the default route to tell whether a
/// proxy-based VPN client is actually carrying traffic. Read-only.
public struct NetworkProbe: Sendable {
    private let runner: CommandRunner

    public init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    public func localProxyEnabled() async -> Bool {
        guard let result = try? await runner.run("/usr/sbin/scutil", ["--proxy"], timeout: .seconds(5)), result.succeeded
        else { return false }
        return NetworkRouting.localProxyEnabled(scutilProxyOutput: result.output)
    }

    public func defaultInterface() async -> String? {
        guard let result = try? await runner.run("/sbin/route", ["-n", "get", "default"], timeout: .seconds(5)),
            result.succeeded
        else { return nil }
        return NetworkRouting.defaultInterface(routeOutput: result.output)
    }
}
