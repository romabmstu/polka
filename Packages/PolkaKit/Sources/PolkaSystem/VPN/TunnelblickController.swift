import Foundation
import PolkaCore

/// Talks to Tunnelblick through its AppleScript dictionary. Scripts are
/// constants; configuration names travel as `argv`.
public struct TunnelblickController: Sendable {
    public enum Failure: Error, Equatable {
        case notAuthorized
        case invalidName
        case scriptFailed(String)
    }

    private let runner: CommandRunner

    public init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    /// Configurations and their states. Only call while Tunnelblick runs:
    /// talking to it starts it otherwise.
    public func connections() async throws -> [VPNConnection] {
        let script = """
            on run
                set fs to character id 31
                set rs to character id 30
                set out to ""
                tell application id "\(Tunnelblick.bundleID)"
                    set configNames to get name of configurations
                    set configStates to get state of configurations
                    if (count of configNames) is not (count of configStates) then error "Configuration list changed"
                    repeat with i from 1 to (count of configNames)
                        set out to out & (item i of configNames) & fs & (item i of configStates) & rs
                    end repeat
                end tell
                return out
            end run
            """
        return Tunnelblick.connections(fromScriptOutput: try await run(script, []))
    }

    public func connect(_ name: String) async throws {
        guard Tunnelblick.isValidConfigurationName(name) else { throw Failure.invalidName }
        _ = try await run(
            "on run argv\ntell application id \"\(Tunnelblick.bundleID)\" to connect (item 1 of argv)\nend run", [name])
    }

    public func disconnect(_ name: String) async throws {
        guard Tunnelblick.isValidConfigurationName(name) else { throw Failure.invalidName }
        _ = try await run(
            "on run argv\ntell application id \"\(Tunnelblick.bundleID)\" to disconnect (item 1 of argv)\nend run", [name])
    }

    /// Names of installed configurations, read from disk without starting
    /// Tunnelblick: private ones in the user's Library, shared ones in /Library.
    public static func installedConfigurationNames() -> [String] {
        let manager = FileManager.default
        let folders = [
            manager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Tunnelblick/Configurations"),
            URL(filePath: "/Library/Application Support/Tunnelblick/Shared"),
        ]
        let files = folders.flatMap { (try? manager.contentsOfDirectory(atPath: $0.path(percentEncoded: false))) ?? [] }
        return Tunnelblick.configurationNames(fromFileNames: files)
    }

    private func run(_ script: String, _ arguments: [String]) async throws -> String {
        let result = try await runner.run("/usr/bin/osascript", ["-"] + arguments, input: script, timeout: .seconds(15))
        guard result.succeeded else {
            if result.errorOutput.contains("-1743") { throw Failure.notAuthorized }
            throw Failure.scriptFailed(result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.output.trimmingCharacters(in: .newlines)
    }
}
