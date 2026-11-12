import Foundation
import Network

/// Whether this Mac has a network connection, as macOS sees it. Nothing is
/// sent anywhere: the system reports the state of its own interfaces.
public final class NetworkStatus: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var online = true
    private var started = false

    public init() {}

    deinit { monitor.cancel() }

    /// `true` until macOS says otherwise, so a missing answer never reads
    /// as "offline".
    public var isOnline: Bool { lock.withLock { online } }

    public func start() {
        let first = lock.withLock {
            defer { started = true }
            return !started
        }
        guard first else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let reachable = path.status == .satisfied
            self.lock.withLock { self.online = reachable }
        }
        monitor.start(queue: DispatchQueue(label: "io.github.romabmstu.Polka.network", qos: .utility))
    }
}
