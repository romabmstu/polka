import CryptoKit
import Foundation
import Testing
@testable import PolkaSystem

@Suite struct ThroneClientTests {
    private func hex(_ value: String) -> Data {
        var result = Data()
        var i = value.startIndex
        while i < value.endIndex {
            let j = value.index(i, offsetBy: 2)
            result.append(UInt8(value[i..<j], radix: 16)!)
            i = j
        }
        return result
    }

    @Test func officialProtocolVector() throws {
        let key = SymmetricKey(data: Data(0..<32))
        let server = hex("a0a1a2a3a4a5a6a7a8a9aaabacadaeaf")
        let client = hex("b0b1b2b3b4b5b6b7b8b9babbbcbdbebf")
        let derived = ThroneClient.derive(key: key, label: "throne-api/1 c2s", server: server, client: client)
        #expect(derived.withUnsafeBytes { Data($0) } == hex("c5956664b2b29a4c000c660e12cb1dee393891d66f5a4370a963731f5d8d45e3"))
        let wire = hex("00000034bbaf22ae010f5f76f0a362090bdd23f882878666caec9cd0dd49fa42b579bf7070c1841466f2f617e15f81c8e40a70d369495f69")
        let nonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 12))
        let payload = wire.dropFirst(4)
        let box = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: payload.dropLast(16), tag: payload.suffix(16))
        let opened = try ChaChaPoly.open(box, using: derived, authenticating: wire.prefix(4))
        #expect(String(decoding: opened, as: UTF8.self) == #"{"method":"GET","path":"/v1/status"}"#)
        var corrupt = wire
        corrupt[corrupt.count - 1] ^= 1
        let invalid = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: corrupt.dropFirst(4).dropLast(16), tag: corrupt.suffix(16))
        #expect(throws: (any Error).self) { try ChaChaPoly.open(invalid, using: derived, authenticating: corrupt.prefix(4)) }
    }

    @Test func localAPIWhenRequested() async throws {
        guard let portText = ProcessInfo.processInfo.environment["POLKA_THRONE_TEST_PORT"],
              let port = UInt16(portText) else { return }
        let client = try ThroneClient(keyText: "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8", port: port)
        #expect(try await client.status() == .disconnected)
        try await client.setConnected(false)
        #expect(try await client.status() == .disconnected)
    }

    @Test func validatesKey() throws {
        _ = try ThroneClient(keyText: "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8")
        #expect(throws: ThroneClient.Failure.self) { try ThroneClient(keyText: "not a key") }
    }
}
