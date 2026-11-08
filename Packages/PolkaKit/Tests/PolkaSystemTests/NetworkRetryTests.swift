import Foundation
import Testing
@testable import PolkaSystem

@Suite struct NetworkRetryTests {
    private actor Attempts {
        private(set) var count = 0
        func next() -> Int { count += 1; return count }
    }

    @Test func retriesTemporaryNetworkFailure() async throws {
        let attempts = Attempts()
        let result = try await NetworkRetry.run(delays: [.zero, .zero]) {
            if await attempts.next() < 3 { throw URLError(.timedOut) }
            return 42
        }
        #expect(result == 42)
        #expect(await attempts.count == 3)
    }

    @Test func doesNotRetryCertificateFailures() async {
        let attempts = Attempts()
        await #expect(throws: URLError.self) {
            try await NetworkRetry.run(delays: [.zero, .zero]) {
                _ = await attempts.next()
                throw URLError(.serverCertificateUntrusted)
            } as Int
        }
        #expect(await attempts.count == 1)
    }

    @Test func stopsAfterLimitedRetries() async {
        let attempts = Attempts()
        await #expect(throws: URLError.self) {
            try await NetworkRetry.run(delays: [.zero, .zero]) {
                _ = await attempts.next()
                throw URLError(.cannotConnectToHost)
            } as Int
        }
        #expect(await attempts.count == 3)
    }

    @Test func doesNotRetryCancelledRequests() async {
        let attempts = Attempts()
        await #expect(throws: URLError.self) {
            try await NetworkRetry.run(delays: [.zero, .zero]) {
                _ = await attempts.next()
                throw URLError(.cancelled)
            } as Int
        }
        #expect(await attempts.count == 1)
    }
}
