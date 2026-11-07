import AppKit
import Observation
import OSLog
import PolkaCore
import PolkaSystem

@MainActor
@Observable
final class UpdateModel {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateManifest)
        case downloading(UpdateManifest)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    let currentBuild = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0

    /// Called when a build newer than the last announced one shows up.
    @ObservationIgnored var onNewUpdate: (UpdateManifest) -> Void = { _ in }
    @ObservationIgnored private var announcedBuild = 0
    @ObservationIgnored private let updater: Updater?
    @ObservationIgnored private var schedule: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "Polka", category: "updates")

    init() {
        updater = (Bundle.main.object(forInfoDictionaryKey: "PolkaUpdatePublicKey") as? String).map {
            Updater(publicKey: $0)
        }
    }

    var available: UpdateManifest? {
        switch state {
        case .available(let manifest), .downloading(let manifest): manifest
        default: nil
        }
    }

    /// Checks shortly after launch and then every 15 minutes while enabled.
    func startAutomaticChecks(preferences: Preferences) {
        schedule?.cancel()
        guard preferences.checkForUpdatesAutomatically else { return }
        schedule = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                await self?.check(channel: preferences.updateChannel, quietly: true)
                try? await Task.sleep(for: .seconds(15 * 60))
            }
        }
    }

    func check(channel: UpdateChannel, quietly: Bool = false) async {
        guard let updater else {
            if !quietly { state = .failed(String(localized: "The update key is missing. Reinstall Polka from the official release.")) }
            return
        }
        if case .downloading = state { return }
        if !quietly { state = .checking }
        do {
            let latest = try await updater.latest(on: channel)
            lastChecked = .now
            if latest.isNewer(thanBuild: currentBuild), latest.runs(on: ProcessInfo.processInfo.operatingSystemVersion) {
                state = .available(latest)
                if latest.build > announcedBuild {
                    announcedBuild = latest.build
                    onNewUpdate(latest)
                }
            } else if !quietly || state == .checking {
                state = .upToDate
            }
        } catch UpdateVerifier.Failure.badMetadataSignature {
            if !quietly { state = .failed(String(localized: "The update information could not be verified. Check the official release page.")) }
        } catch Updater.Failure.badResponse(404) {
            lastChecked = .now
            if !quietly { state = .failed(String(localized: "No signed update is available for this channel. Check the release page or choose another channel.")) }
        } catch {
            log.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            if !quietly { state = .failed(String(localized: "Couldn’t check for updates. Check your connection and try again.")) }
        }
    }

    func install() async {
        guard let updater, let manifest = available, let id = Bundle.main.bundleIdentifier else { return }
        state = .downloading(manifest)
        do {
            let app = try await updater.prepare(manifest, bundleIdentifier: id)
            try Updater.installAndRelaunch(app, replacing: Bundle.main.bundleURL)
        } catch Updater.Failure.notInstalledInApplications {
            state = .failed(String(localized: "Move Polka to the Applications folder, open it from there and try again."))
        } catch {
            log.error("Update failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(String(localized: "The update couldn’t be completed. Check Polka in Applications and try again."))
        }
    }

    var hasFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    var versionDescription: String { "\(currentVersion) (\(currentBuild))" }
}
