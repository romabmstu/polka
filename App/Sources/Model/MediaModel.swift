import AppKit
import Observation
import OSLog
import PolkaCore
import PolkaSystem

/// What is playing and the controls for it.
///
/// Reads real "Now Playing" information through the bundled MediaRemote
/// adapter, so the panel always shows which app it controls. If the adapter
/// is unavailable, it falls back to the keyboard's media keys.
@MainActor
@Observable
final class MediaModel {
    private(set) var nowPlaying: NowPlaying?
    private(set) var artwork: NSImage?
    /// `false` only when the adapter is missing and media keys are not allowed.
    private(set) var canControl = true
    private(set) var usesMediaKeys = false
    private(set) var startMessage: String?
    private(set) var isStartingPlayer = false
    /// Ticks once a second while something plays, to move the progress bar.
    private(set) var clock = Date.now

    @ObservationIgnored private let adapter = NowPlayingAdapter(bundle: .main)
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "Polka", category: "media")

    var isPlaying: Bool { nowPlaying?.isPlaying ?? false }

    func start() {
        guard let adapter else {
            usesMediaKeys = true
            canControl = MediaKeys.isAllowed
            log.error("MediaRemote adapter not found in the app bundle; using media keys")
            return
        }
        adapter.start { [weak self] item in
            Task { @MainActor in self?.apply(item) }
        }
    }

    func stop() {
        adapter?.stop()
        ticker?.cancel()
    }

    private func apply(_ item: NowPlaying?) {
        if item?.artwork != nowPlaying?.artwork || item?.title != nowPlaying?.title {
            artwork = item?.artwork.flatMap(NSImage.init(data:))
        }
        nowPlaying = item
        if item?.appBundleIdentifier == YandexMusicControl.bundleID, item?.isPlaying == true {
            startMessage = nil
        }
        clock = .now
        updateTicker()
    }

    private func updateTicker() {
        if isPlaying, ticker == nil {
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    self?.clock = .now
                }
            }
        } else if !isPlaying {
            ticker?.cancel()
            ticker = nil
        }
    }

    // MARK: Commands

    func playPause() { send(.togglePlayPause, key: .playPause) }
    func next() { send(.nextTrack, key: .next) }
    func previous() { send(.previousTrack, key: .previous) }
    func play() { send(.play, key: .playPause, onlyIf: !isPlaying) }
    func pause() { send(.pause, key: .playPause, onlyIf: isPlaying) }

    func seek(to fraction: Double) {
        guard let adapter, let duration = nowPlaying?.duration, duration > 0 else { return }
        let target = duration * min(max(fraction, 0), 1)
        if var item = nowPlaying {
            item.elapsedTime = target
            item.timestamp = .now
            nowPlaying = item
        }
        Task { try? await adapter.seek(to: target) }
    }

    private func send(_ command: NowPlayingAdapter.Command, key: MediaKeys.Key, onlyIf condition: Bool = true) {
        guard condition else { return }
        if let adapter {
            if nowPlaying?.isPlaying != nil, var item = nowPlaying {
                // Show the new state right away; the adapter confirms it shortly.
                switch command {
                case .togglePlayPause: item.isPlaying.toggle()
                case .play: item.isPlaying = true
                case .pause: item.isPlaying = false
                default: break
                }
                item.elapsedTime = item.elapsed()
                item.timestamp = .now
                nowPlaying = item
                updateTicker()
            }
            Task { [log] in
                do { try await adapter.send(command) } catch {
                    log.error("Media command failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        } else if MediaKeys.isAllowed {
            MediaKeys.press(key)
        } else {
            MediaKeys.requestPermission()
        }
    }

    // MARK: Apps

    /// Starts the preferred player when nothing is playing.
    func openPlayer(bundleID: String) {
        guard !bundleID.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func playPreferredPlayer(bundleID: String) {
        guard !isStartingPlayer else { return }
        guard bundleID == YandexMusicControl.bundleID else {
            openPlayer(bundleID: bundleID)
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            startMessage = String(localized: "The selected player could not be found.")
            return
        }
        guard MediaKeys.isAllowed else {
            // Opening a player does not require Accessibility access. Keep it
            // usable even if macOS has a stale or denied permission entry.
            openPlayer(bundleID: bundleID)
            MediaKeys.requestPermission()
            startMessage = String(localized: "Allow Accessibility access for Polka, then press play again.")
            return
        }
        startMessage = nil
        isStartingPlayer = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] application, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let application, error == nil else {
                    self.isStartingPlayer = false
                    self.startMessage = String(localized: "The selected player could not be opened.")
                    return
                }
                let result = await YandexMusicControl.start(pid: application.processIdentifier)
                self.isStartingPlayer = false
                switch result {
                case .started, .alreadyPlaying: self.startMessage = nil
                case .permissionRequired: self.startMessage = String(localized: "Allow Accessibility access for Polka, then press play again.")
                case .notReady: self.startMessage = String(localized: "Could not start Yandex Music. Open the player and check that a track is selected.")
                }
            }
        }
    }

    /// Brings the app that is playing to the front.
    func showPlayingApp() {
        guard let id = nowPlaying?.appBundleIdentifier,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func appName(bundleID: String) -> String? {
        guard !bundleID.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return FileManager.default.displayName(atPath: url.path(percentEncoded: false))
            .replacingOccurrences(of: ".app", with: "")
    }

    static func appIcon(bundleID: String) -> NSImage? {
        guard !bundleID.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }
}
