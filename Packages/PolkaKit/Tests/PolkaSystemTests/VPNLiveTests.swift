import Foundation
import Testing
import PolkaCore
@testable import PolkaSystem

/// Explicit opt-in test against a disconnected macOS VPN configuration.
@Suite struct VPNLiveTests {
    @Test func connectsAndRestoresSystemVPN() async throws {
        guard let id = ProcessInfo.processInfo.environment["POLKA_SYSTEM_VPN_TEST_ID"], !id.isEmpty else { return }
        let controller = VPNController()
        guard try await controller.status(of: id) == .disconnected else {
            Issue.record("Test VPN must start disconnected")
            return
        }
        do {
            try await controller.connect(id)
            var connected = false
            for _ in 0..<20 {
                let list = try await controller.connections()
                if list.first(where: { $0.id == id })?.status == .connected { connected = true; break }
                try await Task.sleep(for: .seconds(1))
            }
            try await controller.disconnect(id)
            #expect(connected, "The system did not report the VPN connected")
            var stopped = false
            for _ in 0..<15 {
                let list = try await controller.connections()
                if list.first(where: { $0.id == id })?.status == .disconnected { stopped = true; break }
                try await Task.sleep(for: .seconds(1))
            }
            #expect(stopped, "The system did not report the VPN disconnected")
        } catch {
            try? await controller.disconnect(id)
            throw error
        }
    }
}
