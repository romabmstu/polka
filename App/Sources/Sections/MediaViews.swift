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
        .saturation(media.isStalled ? 0 : 1)
        .opacity(media.isStalled ? 0.6 : 1)
        .scaleEffect(media.isPlaying || media.nowPlaying == nil ? 1 : 0.94)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: media.isPlaying)
        .animation(.easeInOut(duration: 0.35), value: media.isStalled)
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
                    Image(systemName: media.reportsPlaying ? "pause.fill" : "play.fill")
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
        let fraction = dragFraction ?? media.progress ?? 0
        VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(media.isStalled ? Theme.warning : Color.white)
                        .frame(width: max(4, proxy.size.width * fraction))
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
            .animation(.easeInOut(duration: 0.35), value: media.isStalled)
            HStack {
                Text(Self.format(media.elapsed))
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

/// The moving waveform while music plays. When the player says it is playing
/// but nothing comes out, an amber sign that breathes slowly instead: a
/// crossed-out Wi-Fi symbol without a connection, a flat line otherwise.
struct PlaybackGlyph: View {
    @Environment(AppModel.self) private var app
    var size: CGFloat = 13

    var body: some View {
        let media = app.media
        if media.isStalled {
            Group {
                if media.isOffline {
                    Image(systemName: "wifi.slash").font(.system(size: size * 0.92, weight: .bold))
                } else {
                    FlatLine(size: size)
                }
            }
            .foregroundStyle(Theme.warning)
            .modifier(Breathing())
            .help(StalledLabel.text(offline: media.isOffline))
            .accessibilityLabel(StalledLabel.text(offline: media.isOffline))
            .transition(.opacity)
        } else {
            Image(systemName: "waveform")
                .font(.system(size: size, weight: .semibold))
                .symbolEffect(.variableColor.iterative, isActive: true)
                .foregroundStyle(.white)
                .transition(.opacity)
        }
    }
}

/// A waveform with no sound in it: five dots on one line.
private struct FlatLine: View {
    var size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.13) {
            ForEach(0..<5, id: \.self) { _ in
                Capsule().frame(width: size * 0.15, height: size * 0.22)
            }
        }
        .frame(height: size)
    }
}

/// Fades in and out slowly. Stands still when Reduce Motion is on.
private struct Breathing: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? 0.4 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { dimmed = true }
            }
    }
}

/// One line saying why nothing is heard. Takes the place of the artist while
/// playback is stalled, so the layout does not jump.
struct StalledLabel: View {
    @Environment(AppModel.self) private var app
    var size: CGFloat = 13

    static func text(offline: Bool) -> Text {
        offline ? Text("No internet. Music is not playing") : Text("No sound on this Mac")
    }

    var body: some View {
        let offline = app.media.isOffline
        HStack(spacing: 6) {
            Image(systemName: offline ? "wifi.slash" : "speaker.slash.fill")
                .font(.system(size: size * 0.9, weight: .semibold))
            Self.text(offline: offline).lineLimit(1)
        }
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(Theme.warning)
        .transition(.opacity)
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
