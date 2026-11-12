import Foundation

/// Tells real playback from a player that only says it is playing.
///
/// A streaming player that loses its connection keeps reporting "playing"
/// while it waits for data. Two things give it away: it reports a playback
/// rate of zero, or no app is sending sound to an output device. Either one
/// has to last for `grace` before playback counts as stalled, so the gap
/// between two tracks is not mistaken for it.
public struct PlaybackWatch: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// Nothing is playing, or the player is paused.
        case idle
        case playing
        /// The player says it is playing, but nothing is coming out.
        case stalled
    }

    /// How long sound may be missing before playback counts as stalled.
    public static let grace: TimeInterval = 3

    public private(set) var state: State = .idle
    /// When sound was last known to be coming out, while it is missing.
    public private(set) var quietSince: Date?

    public init() {}

    /// - Parameters:
    ///   - reportsPlaying: what the player itself says.
    ///   - playbackRate: the rate the player reports; zero while it buffers.
    ///   - soundIsOut: whether any app is sending audio to an output device,
    ///     or `nil` when that is not known.
    @discardableResult
    public mutating func update(
        reportsPlaying: Bool, playbackRate: Double, soundIsOut: Bool?, at now: Date = .now
    ) -> State {
        guard reportsPlaying else {
            quietSince = nil
            state = .idle
            return state
        }
        guard playbackRate <= 0 || soundIsOut == false else {
            quietSince = nil
            state = .playing
            return state
        }
        let since = quietSince ?? now
        quietSince = since
        state = now.timeIntervalSince(since) >= Self.grace ? .stalled : .playing
        return state
    }
}
