import PolkaCore
import SwiftUI

/// Album art, or the playing app's icon when the player provides none.
struct ArtworkView: View {
    @Environment(AppModel.self) private var app
    var size: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        let media = app.media
        Group {
            if let artwork = media.artwork {
                Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .background(Theme.cardHover)
            } else if let id = media.nowPlaying?.appBundleIdentifier, let icon = MediaModel.appIcon(bundleID: id) {
                Image(nsImage: icon).resizable().padding(size * 0.14)
                    .background(Theme.cardHover)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.cardHover)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .scaleEffect(media.isPlaying || media.nowPlaying == nil ? 1 : 0.94)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: media.isPlaying)
    }
}

struct TransportControls: View {
    @Environment(AppModel.self) private var app
    var size: CGFloat

    var body: some View {
        let media = app.media
        HStack(spacing: size * 0.25) {
            Button { media.previous() } label: { Image(systemName: "backward.fill") }
                .buttonStyle(IconButtonStyle(size: size))
                .accessibilityLabel(Text("Previous track"))
            Button {
                if media.nowPlaying == nil, !app.preferences.playerBundleID.isEmpty {
                    media.playPreferredPlayer(bundleID: app.preferences.playerBundleID)
                } else {
                    media.playPause()
                }
            } label: {
                if media.isStartingPlayer {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(IconButtonStyle(size: size * 1.2, filled: true))
            .accessibilityLabel(Text("Play or pause"))
            Button { media.next() } label: { Image(systemName: "forward.fill") }
                .buttonStyle(IconButtonStyle(size: size))
                .accessibilityLabel(Text("Next track"))
        }
        .disabled(!media.canControl || media.isStartingPlayer)
    }
}

/// Playback position; click or drag to seek.
struct PlaybackBar: View {
    @Environment(AppModel.self) private var app
    @State private var dragFraction: Double?

    var body: some View {
        let media = app.media
        let item = media.nowPlaying
        let fraction = dragFraction ?? item?.progress ?? 0
        VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(Color.white).frame(width: max(4, proxy.size.width * fraction))
                }
                .frame(height: dragFraction == nil ? 5 : 7)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { dragFraction = min(max($0.location.x / proxy.size.width, 0), 1) }
                        .onEnded { value in
                            media.seek(to: min(max(value.location.x / proxy.size.width, 0), 1))
                            dragFraction = nil
                        }
                )
            }
            .frame(height: 14)
            .animation(.easeOut(duration: 0.12), value: dragFraction == nil)
            HStack {
                Text(Self.format(item?.elapsed(at: media.clock)))
                Spacer()
                Text(Self.format(item?.duration))
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.tertiary)
        }
        .disabled(item?.duration == nil)
        .opacity(item?.duration == nil ? 0.4 : 1)
    }

    static func format(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "–:––" }
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// "Yandex Music" / "Safari" — which app the controls act on.
struct PlayingSource: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let id = app.media.nowPlaying?.appBundleIdentifier {
            Button {
                app.media.showPlayingApp()
            } label: {
                HStack(spacing: 5) {
                    if let icon = MediaModel.appIcon(bundleID: id) {
                        Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                    }
                    Text(MediaModel.appName(bundleID: id) ?? id).lineLimit(1)
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.tertiary)
            }
            .buttonStyle(.plain)
            .help(Text("Show the app that is playing"))
        }
    }
}
