import Foundation
import Testing
import PolkaCore
@testable import PolkaSystem

/// Opt-in: requires a running Tunnelblick and a disposable disconnected configuration.
@Suite struct TunnelblickLiveTests {
    @Test func connectsAndRestoresConfiguration() async throws {
        guard let name = ProcessInfo.processInfo.environment["POLKA_TUNNELBLICK_TEST_CONFIG"], !name.isEmpty else { return }
        let controller = TunnelblickController()
        let initial = try await controller.connections()
        guard initial.first(where: { $0.name == name })?.status == .disconnected else {
            Issue.record("Test configuration must exist and be disconnected")
            return
        }
        do {
            try await controller.connect(name)
            var connected = false
            for _ in 0..<25 {
                let list = try await controller.connections()
                if list.first(where: { $0.name == name })?.status == .connected { connected = true; break }
                try await Task.sleep(for: .seconds(1))
            }
            try await controller.disconnect(name)
            #expect(connected, "Tunnelblick never reported connected")
            var stopped = false
            for _ in 0..<15 {
                let list = try await controller.connections()
                if list.first(where: { $0.name == name })?.status == .disconnected { stopped = true; break }
                try await Task.sleep(for: .seconds(1))
            }
            #expect(stopped, "Tunnelblick did not disconnect")
        } catch {
            try? await controller.disconnect(name)
            throw error
        }
    }
}
