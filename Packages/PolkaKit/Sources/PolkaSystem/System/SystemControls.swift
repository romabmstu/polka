import Foundation
import PolkaCore

/// Dark mode and sound volume, for scenarios. Scripts are constants; values
/// arrive as `argv` and are validated before that.
public struct SystemControls: Sendable {
    public enum Failure: Error, Equatable {
        /// The user has not allowed Polka to control System Events.
        case notAuthorized
        case scriptFailed(String)
    }

    private let runner: CommandRunner

    public init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    /// Needs Automation permission for System Events, which macOS asks for
    /// the first time.
    public func setAppearance(_ appearance: Scenario.Appearance) async throws {
        let script = """
            on run argv
                tell application id "com.apple.systemevents"
                    tell appearance preferences
                        if item 1 of argv is "toggle" then
                            set dark mode to not dark mode
                        else
                            set dark mode to (item 1 of argv is "dark")
                        end if
                    end tell
                end tell
            end run
            """
        try await run(script, [appearance.rawValue])
    }

    public func outputVolume() async throws -> Int {
        let result = try await runner.runChecked("/usr/bin/osascript", ["-e", "output volume of (get volume settings)"], timeout: .seconds(5))
        guard let value = Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)), (0...100).contains(value) else {
            throw Failure.scriptFailed("Unable to read output volume")
        }
        return value
    }

    public func setVolume(percent: Int) async throws {
        let value = Scenario.clampedVolume(percent)
        try await run("on run argv\nset volume output volume ((item 1 of argv) as integer) without output muted\nend run", [String(value)])
    }

    public func setMuted(_ muted: Bool) async throws {
        try await run("on run argv\nset volume output muted ((item 1 of argv) is \"true\")\nend run", [muted ? "true" : "false"])
    }

    private func run(_ script: String, _ arguments: [String]) async throws {
        let result = try await runner.run("/usr/bin/osascript", ["-"] + arguments, input: script, timeout: .seconds(10))
        guard result.succeeded else {
            if result.errorOutput.contains("-1743") { throw Failure.notAuthorized }
            throw Failure.scriptFailed(result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
