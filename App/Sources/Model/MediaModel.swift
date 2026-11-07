import AppKit
import Observation
import PolkaSystem

/// Play/pause and track controls for whichever app is playing.
@MainActor
@Observable
final class MediaModel {
    private(set) var isAllowed = MediaKeys.isAllowed
    /// Best guess only: the system does not tell third-party apps whether
    /// something is playing, so this follows the user's own presses.
    private(set) var assumedPlaying = false

    func refreshPermission() {
        isAllowed = MediaKeys.isAllowed
    }

    func requestPermission() {
        MediaKeys.requestPermission()
    }

    func playPause() { send(.playPause) { $0.assumedPlaying.toggle() } }
    func next() { send(.next) { $0.assumedPlaying = true } }
    func previous() { send(.previous) { $0.assumedPlaying = true } }

    func play() { if !assumedPlaying { playPause() } }
    func pause() { if assumedPlaying { playPause() } }

    private func send(_ key: MediaKeys.Key, then update: (MediaModel) -> Void) {
        refreshPermission()
        guard isAllowed else {
            requestPermission()
            return
        }
        if MediaKeys.press(key) { update(self) }
    }

    /// Launches or focuses the player chosen in Settings.
    func openPlayer(bundleID: String) {
        guard !bundleID.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func playerName(bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path(percentEncoded: false))
            .replacingOccurrences(of: ".app", with: "")
    }
}
