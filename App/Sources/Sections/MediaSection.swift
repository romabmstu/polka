import PolkaCore
import PolkaSystem
import SwiftUI

struct MediaSection: View {
    @Environment(AppModel.self) private var app
    @State private var volume: Double = 0
    @State private var volumeAvailable = false
    @State private var editingVolume = false
    @State private var volumeError = false
    private let system = SystemControls()

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
                    volumeControl
                    HStack {
                        TransportControls(size: 42)
                        Spacer()
                        playerButton
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            .background(Theme.card, in: .rect(cornerRadius: 22))
            .frame(maxHeight: .infinity, alignment: .center)
            .task {
                while !Task.isCancelled {
                    if !editingVolume {
                        let value = try? await system.outputVolume()
                        if !editingVolume {
                            if let value { volume = Double(value) }
                            volumeAvailable = value != nil
                        }
                    }
                    try? await Task.sleep(for: .seconds(10))
                }
            }
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 10) {
            Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .foregroundStyle(Theme.secondary)
            Slider(value: $volume, in: 0...100, onEditingChanged: { editing in
                editingVolume = editing
                if !editing {
                    let value = Int(volume.rounded())
                    Task {
                        do { try await system.setVolume(percent: value); volumeError = false }
                        catch { volumeError = true }
                    }
                }
            }) { Text("System volume") }
            .disabled(!volumeAvailable)
            if volumeError {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            }
            Text(volumeAvailable ? "\(Int(volume.rounded()))%" : "—")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.secondary).frame(width: 36, alignment: .trailing)
        }
        .help(volumeError ? Text("Could not change system volume") : (volumeAvailable ? Text("System volume") : Text("System volume unavailable")))
    }

    @ViewBuilder
    private var playerButton: some View {
        let preferred = app.preferences.playerBundleID
        HStack(spacing: 8) {
            if let name = MediaModel.appName(bundleID: preferred), app.media.nowPlaying?.appBundleIdentifier != preferred {
                Button { app.media.openPlayer(bundleID: preferred) } label: {
                    Label("Open \(name)", systemImage: "arrow.up.forward.app")
                }.buttonStyle(CapsuleButtonStyle())
            }
            Button("Choose your player…") { app.settingsPage = .music; app.openSettings() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
        }
    }
}
