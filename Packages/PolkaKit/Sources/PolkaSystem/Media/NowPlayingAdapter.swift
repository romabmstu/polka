import Foundation
import PolkaCore

/// Reads "Now Playing" information and sends playback commands for whatever
/// app is playing.
///
/// Since macOS 15.4 only Apple-signed processes may use the MediaRemote
/// framework, so this runs the bundled MediaRemote Adapter inside
/// `/usr/bin/perl` (see `Vendor/MediaRemoteAdapter`). Arguments are fixed;
/// nothing user-provided reaches the process.
public final class NowPlayingAdapter: @unchecked Sendable {
    public enum Command: Int, Sendable {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    private static let perl = "/usr/bin/perl"
    private let script: URL
    private let framework: URL
    private let runner = CommandRunner()
    /// Guards the mutable state below, which is touched from pipe and
    /// termination callbacks on arbitrary threads.
    private let lock = NSLock()
    private var process: Process?
    private var buffer = Data()
    private var stopped = true
    private var restarts = 0

    /// Looks for the adapter inside an app bundle: the script in Resources and
    /// the framework in Frameworks.
    public convenience init?(bundle: Bundle) {
        guard
            let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let frameworks = bundle.privateFrameworksURL
        else { return nil }
        let framework = frameworks.appending(path: "MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: framework.path(percentEncoded: false)) else { return nil }
        self.init(script: script, framework: framework)
    }

    public init(script: URL, framework: URL) {
        self.script = script
        self.framework = framework
    }

    /// Starts streaming updates. `onUpdate` receives `nil` when nothing plays.
    /// The helper is restarted if it exits, with a growing delay.
    public func start(onUpdate: @escaping @Sendable (NowPlaying?) -> Void) {
        let alreadyRunning = lock.withLock {
            stopped = false
            return process != nil
        }
        guard !alreadyRunning else { return }
        launch(onUpdate: onUpdate)
    }

    public func stop() {
        let running = lock.withLock {
            stopped = true
            defer { process = nil }
            return process
        }
        running?.terminate()
    }

    public func send(_ command: Command) async throws {
        try await run(["send", String(command.rawValue)])
    }

    public func seek(to seconds: TimeInterval) async throws {
        let micros = max(0, Int((seconds * 1_000_000).rounded()))
        try await run(["seek", String(micros)])
    }

    private func run(_ arguments: [String]) async throws {
        try await runner.runChecked(
            Self.perl,
            [script.path(percentEncoded: false), framework.path(percentEncoded: false)] + arguments,
            timeout: .seconds(5))
    }

    private func launch(onUpdate: @escaping @Sendable (NowPlaying?) -> Void) {
        let process = Process()
        process.executableURL = URL(filePath: Self.perl)
        process.arguments = [
            script.path(percentEncoded: false), framework.path(percentEncoded: false),
            "stream", "--no-diff", "--micros", "--debounce=120",
        ]
        process.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self, !chunk.isEmpty else { return }
            for line in self.appendAndSplit(chunk) {
                if case .update(let item) = NowPlaying.parse(line: line) { onUpdate(item) }
            }
        }

        let reader = UncheckedBox(output.fileHandleForReading)
        process.terminationHandler = { [weak self] _ in
            reader.value.readabilityHandler = nil
            guard let self else { return }
            let (shouldRestart, attempt) = self.lock.withLock {
                self.process = nil
                self.buffer.removeAll()
                self.restarts += 1
                return (!self.stopped, self.restarts)
            }
            guard shouldRestart, attempt <= 20 else { return }
            onUpdate(nil)
            let delay = min(30.0, pow(2.0, Double(attempt)))
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, !self.lock.withLock({ self.stopped }) else { return }
                self.launch(onUpdate: onUpdate)
            }
        }

        do {
            try process.run()
            lock.withLock { self.process = process }
        } catch {
            onUpdate(nil)
        }
    }

    /// Accumulates output and returns complete lines. Lines are bounded so a
    /// misbehaving helper cannot grow memory without limit.
    private func appendAndSplit(_ chunk: Data) -> [Data] {
        lock.withLock {
            buffer.append(chunk)
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                lines.append(Data(buffer[buffer.startIndex..<newline]))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            if buffer.count > 16 * 1024 * 1024 { buffer.removeAll() }
            if !lines.isEmpty { restarts = 0 }
            return lines
        }
    }
}

/// Carries a reference across a `@Sendable` boundary where the value is only
/// used in a thread-safe way (here: clearing a file handle's callback).
private final class UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
