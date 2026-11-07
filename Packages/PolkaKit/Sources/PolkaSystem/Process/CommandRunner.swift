import Foundation
import os

public struct CommandResult: Sendable {
    public let exitStatus: Int32
    public let output: String
    public let errorOutput: String

    public var succeeded: Bool { exitStatus == 0 }
}

public enum CommandError: Error, Equatable {
    case launchFailed(String)
    case timedOut
    case failed(status: Int32, message: String)
}

/// Runs system tools without a shell.
///
/// The executable is an absolute path and arguments are passed as a list, so
/// nothing a user types can be interpreted by a shell. The environment is
/// reduced to a fixed `PATH` and an English locale to keep output parseable.
public struct CommandRunner: Sendable {
    public init() {}

    public func run(
        _ executable: String,
        _ arguments: [String],
        input: String? = nil,
        timeout: Duration = .seconds(20)
    ) async throws -> CommandResult {
        let job = Job(executable: executable, arguments: arguments)
        return try await withTaskCancellationHandler {
            try await job.start(input: input, timeout: timeout)
        } onCancel: {
            job.terminate()
        }
    }

    /// Like `run`, but throws when the tool exits with a non-zero status.
    @discardableResult
    public func runChecked(
        _ executable: String,
        _ arguments: [String],
        input: String? = nil,
        timeout: Duration = .seconds(20)
    ) async throws -> CommandResult {
        let result = try await run(executable, arguments, input: input, timeout: timeout)
        guard result.succeeded else {
            let message = result.errorOutput.isEmpty ? result.output : result.errorOutput
            throw CommandError.failed(status: result.exitStatus, message: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result
    }
}

/// Owns one `Process` and its pipes. Mutable state is behind a lock, which is
/// what makes the unchecked `Sendable` conformance sound.
private final class Job: @unchecked Sendable {
    private let process = Process()
    private let stdout = Pipe()
    private let stderr = Pipe()
    private let stdin = Pipe()
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var output = Data()
        var errorOutput = Data()
        var timedOut = false
    }

    private static let maximumOutput = 4 * 1024 * 1024

    init(executable: String, arguments: [String]) {
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"]
        process.standardOutput = stdout
        process.standardError = stderr
    }

    func start(input: String?, timeout: Duration) async throws -> CommandResult {
        if input == nil {
            process.standardInput = FileHandle.nullDevice
        } else {
            process.standardInput = stdin
        }

        stdout.fileHandleForReading.readabilityHandler = { [state] handle in
            let chunk = handle.availableData
            state.withLock { if $0.output.count < Self.maximumOutput { $0.output.append(chunk) } }
        }
        stderr.fileHandleForReading.readabilityHandler = { [state] handle in
            let chunk = handle.availableData
            state.withLock { if $0.errorOutput.count < Self.maximumOutput { $0.errorOutput.append(chunk) } }
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { [self] finished in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                let restOut = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
                let restErr = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
                let snapshot = state.withLock { state -> State in
                    state.output.append(restOut)
                    state.errorOutput.append(restErr)
                    return state
                }
                if snapshot.timedOut {
                    continuation.resume(throwing: CommandError.timedOut)
                } else {
                    continuation.resume(
                        returning: CommandResult(
                            exitStatus: finished.terminationStatus,
                            output: String(decoding: snapshot.output, as: UTF8.self),
                            errorOutput: String(decoding: snapshot.errorOutput, as: UTF8.self)
                        ))
                }
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: CommandError.launchFailed(error.localizedDescription))
                return
            }

            if let input {
                let writer = stdin.fileHandleForWriting
                try? writer.write(contentsOf: Data(input.utf8))
                try? writer.close()
            }

            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.expire()
            }
        }
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    private func expire() {
        guard process.isRunning else { return }
        state.withLock { $0.timedOut = true }
        process.terminate()
    }
}
