import CryptoKit
import Foundation

public enum UpdateChannel: String, Codable, CaseIterable, Sendable {
    /// Tagged releases.
    case stable
    /// A build of every change pushed to `main`.
    case beta
}

/// Describes one downloadable build. Published next to the build as
/// `update.json`; the zip it points to is signed with the project's Ed25519 key.
public struct UpdateManifest: Codable, Equatable, Sendable {
    public var version: String
    public var build: Int
    public var channel: UpdateChannel
    public var url: URL
    public var size: Int
    public var sha256: String
    public var signature: String
    public var minimumSystemVersion: String
    public var notes: String
    public var publishedAt: Date
    /// Signature of the update metadata; the archive has its own signature.
    public var metadataSignature: String?

    public init(
        version: String, build: Int, channel: UpdateChannel, url: URL, size: Int, sha256: String,
        signature: String, minimumSystemVersion: String, notes: String, publishedAt: Date, metadataSignature: String? = nil
    ) {
        self.version = version
        self.build = build
        self.channel = channel
        self.url = url
        self.size = size
        self.sha256 = sha256
        self.signature = signature
        self.minimumSystemVersion = minimumSystemVersion
        self.notes = notes
        self.publishedAt = publishedAt
        self.metadataSignature = metadataSignature
    }

    public static func decode(_ data: Data) throws -> UpdateManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UpdateManifest.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Length-prefixing makes the signed representation unambiguous, even for multiline notes.
    public func metadataPayload() -> Data {
        let fields = ["polka-update-v1", version, String(build), channel.rawValue, url.absoluteString,
                      String(size), sha256, signature, minimumSystemVersion, notes,
                      ISO8601DateFormatter().string(from: publishedAt)]
        return Data(fields.map { "\($0.utf8.count):\($0)" }.joined().utf8)
    }

    /// Builds are numbered by the commit count of `main`, so a higher number is
    /// always newer, whichever channel it came from.
    public func isNewer(thanBuild current: Int) -> Bool { build > current }

    public func runs(on system: OperatingSystemVersion) -> Bool {
        let parts = minimumSystemVersion.split(separator: ".").compactMap { Int($0) }
        let required = OperatingSystemVersion(
            majorVersion: parts.first ?? 0,
            minorVersion: parts.count > 1 ? parts[1] : 0,
            patchVersion: parts.count > 2 ? parts[2] : 0)
        return (system.majorVersion, system.minorVersion, system.patchVersion)
            >= (required.majorVersion, required.minorVersion, required.patchVersion)
    }
}

/// Checks that a downloaded update is exactly what the project published.
public enum UpdateVerifier {
    public enum Failure: Error, Equatable {
        case wrongSize
        case checksumMismatch
        case badSignature
        case invalidKey
        case untrustedLocation
        case badMetadataSignature
    }

    /// Updates are only ever fetched from this repository's releases.
    public static let allowedURLPrefix = "https://github.com/romabmstu/polka/releases/download/"

    public static func checkLocation(_ manifest: UpdateManifest) throws(Failure) {
        guard manifest.url.absoluteString.hasPrefix(allowedURLPrefix), !manifest.url.absoluteString.contains("..")
        else { throw .untrustedLocation }
    }

    public static func verifyMetadata(_ manifest: UpdateManifest, publicKey: String) throws(Failure) {
        guard let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { throw .invalidKey }
        guard let encoded = manifest.metadataSignature, let signature = Data(base64Encoded: encoded),
              key.isValidSignature(signature, for: manifest.metadataPayload()) else { throw .badMetadataSignature }
    }

    public static func verify(_ archive: Data, against manifest: UpdateManifest, publicKey: String) throws(Failure) {
        guard archive.count == manifest.size else { throw .wrongSize }
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard digest == manifest.sha256.lowercased() else { throw .checksumMismatch }
        guard
            let keyData = Data(base64Encoded: publicKey),
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { throw .invalidKey }
        guard let signature = Data(base64Encoded: manifest.signature), key.isValidSignature(signature, for: archive)
        else { throw .badSignature }
    }
}
