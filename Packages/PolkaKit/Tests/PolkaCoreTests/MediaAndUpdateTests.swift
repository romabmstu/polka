import CryptoKit
import Foundation
import Testing

@testable import PolkaCore

@Suite struct NowPlayingTests {
    @Test func parsesStreamLine() throws {
        let line = """
            {"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.WebKit.GPU",\
            "parentApplicationBundleIdentifier":"com.apple.Safari","title":"Song","artist":"Band",\
            "durationMicros":200000000,"elapsedTimeMicros":50000000,"timestampEpochMicros":1700000000000000,\
            "playing":true,"playbackRate":1}}
            """
        guard case .update(let item?) = NowPlaying.parse(line: Data(line.utf8)) else {
            Issue.record("expected an update")
            return
        }
        #expect(item.appBundleIdentifier == "com.apple.Safari")
        #expect(item.title == "Song")
        #expect(item.duration == 200)
        let later = Date(timeIntervalSince1970: 1_700_000_010)
        #expect(item.elapsed(at: later) == 60)
    }

    @Test func emptyPayloadMeansNothingPlaying() {
        #expect(NowPlaying.parse(line: Data(#"{"type":"data","diff":false,"payload":{}}"#.utf8)) == .update(nil))
    }

    @Test func ignoresNoise() {
        #expect(NowPlaying.parse(line: Data("not json".utf8)) == .ignored)
    }

    @Test func pausedPositionDoesNotMove() {
        let item = NowPlaying(
            bundleIdentifier: "x", title: "t", duration: 100, elapsedTime: 30, timestamp: .distantPast, isPlaying: false)
        #expect(item.elapsed() == 30)
    }
}

@Suite struct UpdateTests {
    private let key = Curve25519.Signing.PrivateKey()

    private func manifest(for archive: Data, signature: Data? = nil) throws -> UpdateManifest {
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        return UpdateManifest(
            version: "0.2.0", build: 42, channel: .beta,
            url: URL(string: "https://github.com/romabmstu/polka/releases/download/nightly/Polka.zip")!,
            size: archive.count, sha256: digest,
            signature: (try signature ?? key.signature(for: archive)).base64EncodedString(),
            minimumSystemVersion: "14.0", notes: "", publishedAt: .now)
    }

    private var publicKey: String { key.publicKey.rawRepresentation.base64EncodedString() }

    @Test func acceptsSignedArchive() throws {
        let archive = Data("polka".utf8)
        try UpdateVerifier.verify(archive, against: try manifest(for: archive), publicKey: publicKey)
    }

    @Test func rejectsTamperedArchive() throws {
        let archive = Data("polka".utf8)
        let m = try manifest(for: archive)
        #expect(throws: UpdateVerifier.Failure.checksumMismatch) {
            try UpdateVerifier.verify(Data("polkA".utf8), against: m, publicKey: publicKey)
        }
    }

    @Test func rejectsForeignSignature() throws {
        let archive = Data("polka".utf8)
        let other = try Curve25519.Signing.PrivateKey().signature(for: archive)
        let m = try manifest(for: archive, signature: other)
        #expect(throws: UpdateVerifier.Failure.badSignature) {
            try UpdateVerifier.verify(archive, against: m, publicKey: publicKey)
        }
    }

    @Test func rejectsOtherLocations() throws {
        var m = try manifest(for: Data("x".utf8))
        m.url = URL(string: "https://example.com/Polka.zip")!
        #expect(throws: UpdateVerifier.Failure.untrustedLocation) { try UpdateVerifier.checkLocation(m) }
    }

    @Test func roundTripsJSON() throws {
        let m = try manifest(for: Data("x".utf8))
        let decoded = try UpdateManifest.decode(try m.encoded())
        #expect(decoded.build == m.build)
        #expect(decoded.signature == m.signature)
    }

    @Test func comparesSystemVersions() throws {
        let m = try manifest(for: Data("x".utf8))
        #expect(m.runs(on: OperatingSystemVersion(majorVersion: 15, minorVersion: 1, patchVersion: 0)))
        #expect(!m.runs(on: OperatingSystemVersion(majorVersion: 13, minorVersion: 6, patchVersion: 0)))
    }
}
