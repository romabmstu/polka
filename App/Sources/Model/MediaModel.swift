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
    /// The player says it is playing, but no sound is coming out: it lost its
    /// connection and is waiting for data, for example.
    private(set) var isStalled = false
    /// The Mac has no network connection while playback is stalled.
    private(set) var isOffline = false

    @ObservationIgnored private let adapter = NowPlayingAdapter(bundle: .main)
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var watch = PlaybackWatch()
    @ObservationIgnored private let network = NetworkStatus()
    @ObservationIgnored private let log = Logger(subsystem: "Polka", category: "media")

    /// What the player itself says, true or not.
    var reportsPlaying: Bool { nowPlaying?.isPlaying ?? false }
    /// Music is actually playing.
    var isPlaying: Bool { reportsPlaying && !isStalled }

    /// Position in the track. It stands still while playback is stalled,
    /// whatever the player reports.
    var elapsed: TimeInterval? {
        nowPlaying?.elapsed(at: isStalled ? (watch.quietSince ?? clock) : clock)
    }

    var progress: Double? {
        guard let duration = nowPlaying?.duration, duration > 0, let elapsed = elapsed else { return nil }
        return min(max(elapsed / duration, 0), 1)
    }

    func start() {
        network.start()
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
        checkPlayback()
        if reportsPlaying, ticker == nil {
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    self?.tick()
                }
            }
        } else if !reportsPlaying {
            ticker?.cancel()
            ticker = nil
        }
    }

    private func tick() {
        checkPlayback()
        if !isStalled { clock = .now }
    }

    /// Compares what the player says with what can be heard.
    private func checkPlayback() {
        let state = watch.update(
            reportsPlaying: reportsPlaying,
            playbackRate: nowPlaying?.playbackRate ?? 1,
            soundIsOut: reportsPlaying ? AudioActivity.isOutputRunning() : nil)
        let stalled = state == .stalled
        let offline = stalled && !network.isOnline
        if stalled != isStalled {
            isStalled = stalled
            log.info("Playback \(stalled ? "stalled" : "resumed", privacy: .public)")
        }
        if offline != isOffline { isOffline = offline }
    }

    // MARK: Commands

    func playPause() { send(.togglePlayPause, key: .playPause) }
    func next() { send(.nextTrack, key: .next) }
    func previous() { send(.previousTrack, key: .previous) }
    func play() { send(.play, key: .playPause, onlyIf: !reportsPlaying) }
    func pause() { send(.pause, key: .playPause, onlyIf: reportsPlaying) }

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
        Task { [weak self] in
            guard let self else { return }
            do {
                let application = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                let result = await YandexMusicControl.start(pid: application.processIdentifier)
                self.isStartingPlayer = false
                switch result {
                case .started, .alreadyPlaying: self.startMessage = nil
                case .permissionRequired: self.startMessage = String(localized: "Allow Accessibility access for Polka, then press play again.")
                case .notReady: self.startMessage = String(localized: "Could not start Yandex Music. Open the player and check that a track is selected.")
                }
            } catch {
                self.isStartingPlayer = false
                self.startMessage = String(localized: "The selected player could not be opened.")
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
