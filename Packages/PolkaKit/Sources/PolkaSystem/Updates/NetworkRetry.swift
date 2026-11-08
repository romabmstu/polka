import Foundation

/// Retry transient transport failures, never signature or HTTP validation errors.
enum NetworkRetry {
    static func run<T: Sendable>(delays: [Duration] = [.seconds(1), .seconds(3)],
                                 operation: @Sendable () async throws -> T) async throws -> T {
        for delay in delays {
            try Task.checkCancellation()
            do { return try await operation() }
            catch let error as URLError where isTransient(error) {
                try await Task.sleep(for: delay)
            }
        }
        try Task.checkCancellation()
        return try await operation()
    }

    static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
             .dnsLookupFailed, .notConnectedToInternet:
            true
        default:
            false
        }
    }
}
