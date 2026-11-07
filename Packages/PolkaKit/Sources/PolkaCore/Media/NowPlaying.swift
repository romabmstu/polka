import Foundation

/// What the system reports as playing right now, in any app.
public struct NowPlaying: Equatable, Sendable {
    public var bundleIdentifier: String
    /// Set for media playing inside another app, e.g. a web player in Safari.
    public var parentBundleIdentifier: String?
    public var title: String
    public var artist: String?
    public var album: String?
    public var duration: TimeInterval?
    public var elapsedTime: TimeInterval?
    /// When `elapsedTime` was measured.
    public var timestamp: Date?
    public var isPlaying: Bool
    public var playbackRate: Double
    public var artwork: Data?

    public init(
        bundleIdentifier: String,
        parentBundleIdentifier: String? = nil,
        title: String,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval? = nil,
        elapsedTime: TimeInterval? = nil,
        timestamp: Date? = nil,
        isPlaying: Bool,
        playbackRate: Double = 1,
        artwork: Data? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.parentBundleIdentifier = parentBundleIdentifier
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.timestamp = timestamp
        self.isPlaying = isPlaying
        self.playbackRate = playbackRate
        self.artwork = artwork
    }

    /// The app to show and to bring forward: the browser, not its helper process.
    public var appBundleIdentifier: String { parentBundleIdentifier ?? bundleIdentifier }

    /// Playback position at `date`, extrapolated while playing.
    public func elapsed(at date: Date = .now) -> TimeInterval? {
        guard let elapsedTime else { return nil }
        guard isPlaying, let timestamp else { return elapsedTime }
        let value = elapsedTime + max(0, date.timeIntervalSince(timestamp)) * max(playbackRate, 0)
        if let duration, duration > 0 { return min(value, duration) }
        return value
    }

    public var progress: Double? {
        guard let duration, duration > 0, let elapsed = elapsed() else { return nil }
        return min(max(elapsed / duration, 0), 1)
    }
}

extension NowPlaying {
    /// One line of `mediaremote-adapter stream --micros --no-diff` output.
    private struct StreamLine: Decodable {
        var type: String
        var payload: Payload?
    }

    private struct Payload: Decodable {
        var bundleIdentifier: String?
        var parentApplicationBundleIdentifier: String?
        var title: String?
        var artist: String?
        var album: String?
        var durationMicros: Double?
        var elapsedTimeMicros: Double?
        var timestampEpochMicros: Double?
        var playing: Bool?
        var playbackRate: Double?
        var artworkData: String?
    }

    public enum ParseResult: Equatable, Sendable {
        /// A full state update; `nil` means nothing is playing.
        case update(NowPlaying?)
        /// Not a data line (or not one we understand); ignore it.
        case ignored
    }

    /// Artwork larger than this is dropped rather than decoded.
    public static let maximumArtworkSize = 4 * 1024 * 1024

    public static func parse(line: Data) -> ParseResult {
        guard let decoded = try? JSONDecoder().decode(StreamLine.self, from: line), decoded.type == "data" else {
            return .ignored
        }
        guard
            let payload = decoded.payload,
            let bundle = payload.bundleIdentifier, !bundle.isEmpty,
            let title = payload.title, !title.isEmpty
        else { return .update(nil) }

        var artwork: Data?
        if let base64 = payload.artworkData, base64.utf8.count <= maximumArtworkSize * 4 / 3 + 4 {
            artwork = Data(base64Encoded: base64)
        }
        return .update(
            NowPlaying(
                bundleIdentifier: bundle,
                parentBundleIdentifier: payload.parentApplicationBundleIdentifier,
                title: title,
                artist: payload.artist?.nilIfEmpty,
                album: payload.album?.nilIfEmpty,
                duration: payload.durationMicros.map { $0 / 1_000_000 },
                elapsedTime: payload.elapsedTimeMicros.map { $0 / 1_000_000 },
                timestamp: payload.timestampEpochMicros.map { Date(timeIntervalSince1970: $0 / 1_000_000) },
                isPlaying: payload.playing ?? false,
                playbackRate: payload.playbackRate ?? 1,
                artwork: artwork
            ))
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
