import CryptoKit
import Darwin
import Foundation
import PolkaCore
import Security

/// Throne API v1. Only loopback is supported: the key grants full local control.
public struct ThroneClient: Sendable {
    public enum Failure: Error { case invalidKey, connection, protocolError, rejected(Int) }
    private let key: SymmetricKey
    private let port: UInt16

    public init(keyText: String, port: UInt16 = 9095) throws {
        let text = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard text.count == 43, let bytes = Data(base64Encoded: text + "="), bytes.count == 32 else {
            throw Failure.invalidKey
        }
        key = SymmetricKey(data: bytes)
        self.port = port
    }

    public func status() async throws -> VPNConnection.Status {
        let response = try await request(method: "GET", path: "/v1/status", body: nil)
        switch response.state {
        case "running": return .connected
        case "connecting": return .connecting
        case "stopping": return .disconnecting
        case "idle": return .disconnected
        default: return .unknown
        }
    }

    public func setConnected(_ connected: Bool) async throws {
        _ = try await request(method: connected ? "PUT" : "DELETE", path: "/v1/connection",
                              body: connected ? ["select": "last", "wait": false] : ["wait": false])
    }

    private struct StatusBody: Decodable, Sendable { let state: String? }
    private struct Response: Decodable { let status: Int; let body: StatusBody? }

    private func request(method: String, path: String, body: [String: any Sendable]?) async throws -> StatusBody {
        // Socket operations and their bounded timeouts never block the main actor.
        try await Task.detached {
            let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { throw Failure.connection }
            defer { Darwin.close(fd) }
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var noSigPipe: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = self.port.bigEndian
            address.sin_addr = in_addr(s_addr: in_addr_t(0x7f000001).bigEndian)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard result == 0 else { throw Failure.connection }
            var nonce = Data(count: 16)
            guard nonce.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }) == errSecSuccess else {
                throw Failure.protocolError
            }
            try Self.writeAll(Data([1]) + nonce, fd: fd)
            let server = try Self.readExactly(16, fd: fd)
            let outgoing = Self.derive(key: self.key, label: "throne-api/1 c2s", server: server, client: nonce)
            let incoming = Self.derive(key: self.key, label: "throne-api/1 s2c", server: server, client: nonce)
            var object: [String: Any] = ["method": method, "path": path]
            if let body { object["body"] = body }
            let plain = try JSONSerialization.data(withJSONObject: object)
            let sealedLength = UInt32(plain.count + 16)
            var bigLength = sealedLength.bigEndian
            let header = withUnsafeBytes(of: &bigLength) { Data($0) }
            let frameNonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 12))
            let sealed = try ChaChaPoly.seal(plain, using: outgoing, nonce: frameNonce, authenticating: header)
            try Self.writeAll(header + sealed.ciphertext + sealed.tag, fd: fd)
            let responseHeader = try Self.readExactly(4, fd: fd)
            let length = responseHeader.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length >= 16, length <= 1_048_576 else { throw Failure.protocolError }
            let frame = try Self.readExactly(Int(length), fd: fd)
            let box = try ChaChaPoly.SealedBox(nonce: frameNonce, ciphertext: frame.dropLast(16), tag: frame.suffix(16))
            let decoded = try ChaChaPoly.open(box, using: incoming, authenticating: responseHeader)
            let response = try JSONDecoder().decode(Response.self, from: decoded)
            guard (200..<300).contains(response.status) else { throw Failure.rejected(response.status) }
            guard let body = response.body else { throw Failure.protocolError }
            return body
        }.value
    }

    static func derive(key: SymmetricKey, label: String, server: Data, client: Data) -> SymmetricKey {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(label.utf8) + server + client, using: key)
        return SymmetricKey(data: Data(mac))
    }

    private static func writeAll(_ data: Data, fd: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let n = Darwin.send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                guard n > 0 else { throw Failure.connection }
                offset += n
            }
        }
    }

    private static func readExactly(_ count: Int, fd: Int32) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < count {
                let n = Darwin.recv(fd, bytes.baseAddress!.advanced(by: offset), count - offset, 0)
                guard n > 0 else { throw Failure.connection }
                offset += n
            }
        }
        return data
    }
}
