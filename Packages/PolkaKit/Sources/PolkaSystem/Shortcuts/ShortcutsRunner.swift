import Foundation
import PolkaCore

/// Lists and runs shortcuts from the Shortcuts app via the `shortcuts` tool.
public struct ShortcutsRunner: Sendable {
    public enum Failure: Error, Equatable {
        case invalidName
    }

    private static let tool = "/usr/bin/shortcuts"
    private let runner: CommandRunner

    public init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    public func names() async throws -> [String] {
        let result = try await runner.runChecked(Self.tool, ["list"], timeout: .seconds(10))
        return result.output.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
    }

    public func run(_ name: String) async throws {
        guard Scenario.isValidShortcutName(name) else { throw Failure.invalidName }
        try await runner.runChecked(Self.tool, ["run", name], timeout: .seconds(60))
    }
}
