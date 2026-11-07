import AppKit
import Foundation
import PolkaCore

/// Finds, downloads and installs new versions from this project's GitHub
/// releases.
///
/// Every archive must match the size and SHA-256 in its manifest and carry a
/// valid Ed25519 signature from the project key embedded in the app, so a
/// compromised download host cannot ship code. The unpacked app must have the
/// same bundle identifier and a valid code signature before it replaces the
/// running copy.
public actor Updater {
    public enum Failure: Error, Equatable {
        case badResponse(Int)
        case tooLarge
        case wrongApp
        case notInstalledInApplications
    }

    public static func manifestURL(for channel: UpdateChannel) -> URL {
        switch channel {
        case .stable: URL(string: "https://github.com/romabmstu/polka/releases/latest/download/update.json")!
        case .beta: URL(string: "https://github.com/romabmstu/polka/releases/download/nightly/update.json")!
        }
    }

    private static let maximumArchiveSize = 200 * 1024 * 1024
    private let session: URLSession
    private let publicKey: String
    private let runner = CommandRunner()

    public init(publicKey: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 600
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        session = URLSession(configuration: configuration)
        self.publicKey = publicKey
    }

    /// The newest build on `channel`, whether or not it is newer than this one.
    public func latest(on channel: UpdateChannel) async throws -> UpdateManifest {
        let (data, response) = try await session.data(from: Self.manifestURL(for: channel))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.badResponse(status) }
        guard data.count <= 64 * 1024 else { throw Failure.tooLarge }
        let manifest = try UpdateManifest.decode(data)
        try UpdateVerifier.checkLocation(manifest)
        try UpdateVerifier.verifyMetadata(manifest, publicKey: publicKey)
        guard manifest.channel == channel else { throw UpdateVerifier.Failure.badMetadataSignature }
        return manifest
    }

    /// Downloads, verifies and unpacks an update; returns the new app bundle.
    public func prepare(_ manifest: UpdateManifest, bundleIdentifier: String) async throws -> URL {
        try UpdateVerifier.checkLocation(manifest)
        try UpdateVerifier.verifyMetadata(manifest, publicKey: publicKey)
        guard manifest.size > 0, manifest.size <= Self.maximumArchiveSize else { throw Failure.tooLarge }

        let (download, response) = try await session.download(from: manifest.url)
        defer { try? FileManager.default.removeItem(at: download) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.badResponse(status) }

        let archive = try Data(contentsOf: download, options: .mappedIfSafe)
        try UpdateVerifier.verify(archive, against: manifest, publicKey: publicKey)

        let workspace = FileManager.default.temporaryDirectory
            .appending(path: "PolkaUpdate-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: workspace, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let zip = workspace.appending(path: "update.zip")
        try archive.write(to: zip)
        let unpacked = workspace.appending(path: "unpacked", directoryHint: .isDirectory)
        try await runner.runChecked(
            "/usr/bin/ditto", ["-x", "-k", zip.path(percentEncoded: false), unpacked.path(percentEncoded: false)],
            timeout: .seconds(120))

        let app = unpacked.appending(path: "Polka.app", directoryHint: .isDirectory)
        guard Bundle(url: app)?.bundleIdentifier == bundleIdentifier else { throw Failure.wrongApp }
        try await runner.runChecked(
            "/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path(percentEncoded: false)],
            timeout: .seconds(60))
        return app
    }

    /// Swaps in the new app and starts it once this process has quit.
    @MainActor
    public static func installAndRelaunch(_ newApp: URL, replacing current: URL) throws {
        // A copy run straight from Downloads is moved to a random read-only
        // path by Gatekeeper and cannot be replaced in place.
        guard !current.path(percentEncoded: false).contains("/AppTranslocation/") else {
            throw Failure.notInstalledInApplications
        }
        _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp, backupItemName: nil, options: [])

        // Fixed script; the process ID and path arrive as positional arguments.
        let relaunch = Process()
        relaunch.executableURL = URL(filePath: "/bin/sh")
        relaunch.arguments = [
            "-c", #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open "$2""#,
            "polka-relaunch", String(ProcessInfo.processInfo.processIdentifier), current.path(percentEncoded: false),
        ]
        try relaunch.run()
        NSApp.terminate(nil)
    }
}
