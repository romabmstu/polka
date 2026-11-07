import SwiftUI

struct MediaSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let media = app.media
        if !media.isAllowed {
            Placeholder(
                symbol: "music.note",
                title: "Control music from the notch",
                message:
                    "Polka presses the same play and track keys as your keyboard. macOS asks once for Accessibility access to allow that."
            ) {
                Button("Allow Access") { media.requestPermission() }
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
                Button("Open Settings") { SystemSettings.open(.accessibility) }
                    .buttonStyle(CapsuleButtonStyle())
            }
        } else {
            HStack(spacing: 24) {
                artwork
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        CardLabel("Now Playing")
                        Text(playerName).font(.system(size: 24, weight: .bold)).lineLimit(1)
                        Text("Works with Yandex Music, Music, Spotify and video in the browser — whatever is playing.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    TransportControls(size: 44)
                    if !app.preferences.playerBundleID.isEmpty {
                        Button {
                            media.openPlayer(bundleID: app.preferences.playerBundleID)
                        } label: {
                            Label("Open \(playerName)", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(CapsuleButtonStyle())
                    } else {
                        Button("Choose a player in Settings…") { app.openSettings() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var playerName: String {
        MediaModel.playerName(bundleID: app.preferences.playerBundleID) ?? String(localized: "Music")
    }

    @ViewBuilder
    private var artwork: some View {
        let playing = app.media.assumedPlaying
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.preferences.playerBundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 180, height: 180)
                .scaleEffect(playing ? 1 : 0.94)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: playing)
        } else {
            Image(systemName: "waveform")
                .font(.system(size: 64, weight: .semibold))
                .symbolEffect(.variableColor.iterative, isActive: playing)
                .frame(width: 180, height: 180)
                .background(Theme.card, in: .rect(cornerRadius: 28, style: .continuous))
        }
    }
}
