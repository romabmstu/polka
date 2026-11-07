import Foundation
import Testing

@testable import PolkaSystem

@Suite struct CommandRunnerTests {
    private let runner = CommandRunner()

    @Test func capturesOutputAndStatus() async throws {
        let result = try await runner.run("/bin/echo", ["hello", "$HOME"])
        #expect(result.succeeded)
        #expect(result.output == "hello $HOME\n")
    }

    @Test func passesInput() async throws {
        let result = try await runner.run("/bin/cat", [], input: "piped")
        #expect(result.output == "piped")
    }

    @Test func reportsFailure() async throws {
        await #expect(throws: CommandError.self) {
            try await runner.runChecked("/usr/bin/false", [])
        }
    }

    @Test func timesOut() async throws {
        await #expect(throws: CommandError.timedOut) {
            try await runner.run("/bin/sleep", ["5"], timeout: .milliseconds(200))
        }
    }

    @Test func handlesLargeOutput() async throws {
        // Far more than a pipe buffer holds; must not deadlock.
        let result = try await runner.run("/usr/bin/seq", ["1", "200000"])
        #expect(result.output.hasSuffix("200000\n"))
    }
}
