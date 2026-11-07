import PolkaCore
import SwiftUI

struct MediaSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let media = app.media
        if !media.canControl {
            Placeholder(
                symbol: "music.note",
                title: "Control music from the notch",
                message: "macOS needs Accessibility access to send the play and track keys."
            ) {
                Button("Open Settings") { SystemSettings.open(.accessibility) }
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
            }
        } else {
            HStack(spacing: 24) {
                ArtworkView(size: 200, cornerRadius: 22)
                    .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        PlayingSource()
                        if let item = media.nowPlaying {
                            Text(item.title)
                                .font(.system(size: 24, weight: .bold))
                                .lineLimit(2)
                            Text([item.artist, item.album].compactMap { $0 }.joined(separator: " — "))
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                        } else {
                            Text("Nothing is playing").font(.system(size: 24, weight: .bold))
                            Text("Start music in any app — Polka shows it here and controls it.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                    PlaybackBar()
                    HStack {
                        TransportControls(size: 42)
                        Spacer()
                        playerButton
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var playerButton: some View {
        let preferred = app.preferences.playerBundleID
        if let name = MediaModel.appName(bundleID: preferred), app.media.nowPlaying?.appBundleIdentifier != preferred {
            Button {
                app.media.openPlayer(bundleID: preferred)
            } label: {
                Label("Open \(name)", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(CapsuleButtonStyle())
        } else if preferred.isEmpty {
            Button("Choose your player…") { app.openSettings() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.tertiary)
        }
    }
}
