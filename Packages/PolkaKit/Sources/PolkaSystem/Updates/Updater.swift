import AppKit
import Foundation
import PolkaCore

/// Finds, downloads and installs new versions from this project's GitHub
/// releases.
///
/// Every archive must match the size and SHA-256 in its manifest and carry a
/// valid Ed25519 signature from the project key embedded in the app, so a
/// compromised download host cannot ship code. The unpacked app must have the
/// same bundle identifier and be signed with the same certificate as the
/// running copy, so macOS keeps the permissions the user granted.
///
/// The previous version is kept until the new one has run for a while: if it
/// crashes right after the update, it is put back automatically.
public actor Updater {
    public enum Failure: Error, Equatable {
        case badResponse(Int)
        case tooLarge
        case wrongApp
        case notInstalledInApplications
    }

    /// Set by the relaunch helper (in the app's defaults) when it put the
    /// previous version back; holds the build that crashed.
    public static let rolledBackBuildKey = "rolledBackFromBuild"
    private static let workspacePrefix = "PolkaUpdate-"

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
        let url = Self.manifestURL(for: channel)
        let session = self.session
        let (data, response) = try await NetworkRetry.run { try await session.data(from: url) }
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

        let session = self.session
        let (download, response) = try await NetworkRetry.run { try await session.download(from: manifest.url) }
        defer { try? FileManager.default.removeItem(at: download) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.badResponse(status) }

        let archive = try Data(contentsOf: download, options: .mappedIfSafe)
        try UpdateVerifier.verify(archive, against: manifest, publicKey: publicKey)

        let workspace = FileManager.default.temporaryDirectory
            .appending(path: Self.workspacePrefix + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: workspace, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            let zip = workspace.appending(path: "update.zip")
            try archive.write(to: zip)
            let unpacked = workspace.appending(path: "unpacked", directoryHint: .isDirectory)
            try await runner.runChecked(
                "/usr/bin/ditto", ["-x", "-k", zip.path(percentEncoded: false), unpacked.path(percentEncoded: false)],
                timeout: .seconds(120))
            try? FileManager.default.removeItem(at: zip)

            let app = unpacked.appending(path: "Polka.app", directoryHint: .isDirectory)
            guard Bundle(url: app)?.bundleIdentifier == bundleIdentifier else { throw Failure.wrongApp }
            try CodeSignature.verify(app, requirement: CodeSignature.designatedRequirementOfRunningApp())
            return app
        } catch {
            try? FileManager.default.removeItem(at: workspace)
            throw error
        }
    }

    /// Removes what an interrupted update left behind: unpacked downloads and
    /// a stale copy of the previous version.
    public static func removeLeftovers() {
        let fileManager = FileManager.default
        let hourAgo = Date.now.addingTimeInterval(-3600)
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let temporary = (try? fileManager.contentsOfDirectory(
            at: fileManager.temporaryDirectory, includingPropertiesForKeys: keys)) ?? []
        for item in temporary where item.lastPathComponent.hasPrefix(workspacePrefix) {
            let modified = (try? item.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
            if modified < hourAgo { try? fileManager.removeItem(at: item) }
        }
        if let backup = previousVersionFolder,
            let modified = (try? backup.resourceValues(forKeys: Set(keys)))?.contentModificationDate,
            modified < Date.now.addingTimeInterval(-600)
        {
            try? fileManager.removeItem(at: backup)
        }
    }

    /// Where the previous version waits while the new one proves itself.
    static var previousVersionFolder: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Polka/PreviousVersion", directoryHint: .isDirectory)
    }

    /// Swaps in the new app and starts it once this process has quit.
    ///
    /// A copy of the current version is kept first. The helper that starts the
    /// new version watches it for 90 seconds; if it exits with a crash report
    /// in that time, the helper puts the previous version back, records
    /// `newBuild` under `rolledBackBuildKey` and starts it.
    @MainActor
    public static func installAndRelaunch(_ newApp: URL, replacing current: URL, newBuild: Int) throws {
        // A copy run straight from Downloads is moved to a random read-only
        // path by Gatekeeper and cannot be replaced in place.
        guard !current.path(percentEncoded: false).contains("/AppTranslocation/") else {
            throw Failure.notInstalledInApplications
        }
        let fileManager = FileManager.default
        let backup = keepPreviousVersion(of: current)
        do {
            _ = try fileManager.replaceItemAt(current, withItemAt: newApp, backupItemName: nil, options: [])
        } catch {
            if let backup { try? fileManager.removeItem(at: backup.deletingLastPathComponent()) }
            throw error
        }
        // The download folder: .../PolkaUpdate-UUID/unpacked/Polka.app
        try? fileManager.removeItem(at: newApp.deletingLastPathComponent().deletingLastPathComponent())

        let marker = fileManager.temporaryDirectory.appending(path: "polka-relaunch-\(UUID().uuidString)")
        // Fixed script; everything it works on arrives as positional arguments.
        let relaunch = Process()
        relaunch.executableURL = URL(filePath: "/bin/sh")
        relaunch.arguments = [
            "-c", relaunchScript, "polka-relaunch",
            String(ProcessInfo.processInfo.processIdentifier),
            current.path(percentEncoded: false),
            backup?.path(percentEncoded: false) ?? "",
            marker.path(percentEncoded: false),
            Bundle.main.bundleIdentifier ?? "io.github.romabmstu.Polka",
            String(newBuild),
        ]
        try relaunch.run()
        NSApp.terminate(nil)
    }

    /// Copies the running app aside; `nil` if that isn't possible (no
    /// space), in which case the update goes ahead without a way back.
    private static func keepPreviousVersion(of current: URL) -> URL? {
        guard let folder = previousVersionFolder else { return nil }
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: folder)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appending(path: current.lastPathComponent, directoryHint: .isDirectory)
            try fileManager.copyItem(at: current, to: copy)
            return copy
        } catch {
            try? fileManager.removeItem(at: folder)
            return nil
        }
    }

    /// $1 pid of this process, $2 the app, $3 the previous version or "",
    /// $4 a marker file path, $5 the defaults domain, $6 the new build.
    static let relaunchScript = #"""
        pid="$1"; app="$2"; backup="$3"; marker="$4"; domain="$5"; build="$6"
        while /bin/kill -0 "$pid" 2>/dev/null; do /bin/sleep 0.2; done
        if [ -z "$backup" ] || [ ! -d "$backup" ]; then
            /usr/bin/open "$app"
            exit 0
        fi
        /usr/bin/touch "$marker"
        /usr/bin/open -W "$app" &
        opener=$!
        waited=0
        while /bin/kill -0 "$opener" 2>/dev/null; do
            if [ "$waited" -ge 90 ]; then
                /bin/kill "$opener" 2>/dev/null
                /bin/rm -rf "$(/usr/bin/dirname "$backup")" "$marker"
                exit 0
            fi
            /bin/sleep 1
            waited=$((waited + 1))
        done
        tries=0
        while [ "$tries" -lt 20 ]; do
            if /usr/bin/find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -name 'Polka*.ips' -newer "$marker" 2>/dev/null | /usr/bin/grep -q .; then
                broken="$app.broken-$$"
                if /bin/mv "$app" "$broken"; then
                    if /bin/mv "$backup" "$app"; then
                        /bin/rm -rf "$broken" "$(/usr/bin/dirname "$backup")"
                        /usr/bin/defaults write "$domain" rolledBackFromBuild -int "$build"
                    else
                        /bin/mv "$broken" "$app"
                    fi
                fi
                /bin/rm -f "$marker"
                /usr/bin/open "$app"
                exit 0
            fi
            /bin/sleep 1
            tries=$((tries + 1))
        done
        /bin/rm -rf "$(/usr/bin/dirname "$backup")" "$marker"
        """#
}
