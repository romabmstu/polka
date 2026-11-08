import PolkaCore
import PolkaSystem
import SwiftUI

struct MediaSection: View {
    @Environment(AppModel.self) private var app
    @State private var volume: Double = 0
    @State private var volumeAvailable = false
    @State private var editingVolume = false
    @State private var volumeError = false
    @State private var outputs: AudioOutputs.Snapshot?
    @State private var outputError = false
    @State private var selectionError = false
    @State private var isWritingVolume = false
    @State private var isChangingOutput = false
    @State private var volumeRevision = 0
    @State private var editedOutputID: UInt32?
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
                    if let message = media.startMessage {
                        HStack {
                            Text(message).font(.system(size: 12)).foregroundStyle(Theme.warning)
                            if !MediaKeys.isAllowed {
                                Button("Open Settings") { SystemSettings.open(.accessibility) }
                                    .buttonStyle(CapsuleButtonStyle())
                            }
                        }
                    }
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
                var tick = 0
                while !Task.isCancelled {
                    if !isChangingOutput {
                        let revision = volumeRevision
                        do {
                            let next = try await Task.detached { try AudioOutputs.snapshot() }.value
                            if revision == volumeRevision && !isChangingOutput {
                                if let previous = outputs, previous.selectedID != next.selectedID {
                                    volumeRevision += 1
                                    tick = 0
                                }
                                outputs = next
                                outputError = false
                            }
                        } catch {
                            if revision == volumeRevision { outputError = true }
                        }
                    }
                    if !editingVolume && !isWritingVolume && !isChangingOutput && tick % 5 == 0 {
                        let revision = volumeRevision
                        let value = try? await system.outputVolume()
                        if !editingVolume && !isWritingVolume && !isChangingOutput && revision == volumeRevision {
                            if let value { volume = Double(value) }
                            volumeAvailable = value != nil
                        }
                    }
                    tick += 1
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    private var volumeControl: some View {
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 10) {
            Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .foregroundStyle(Theme.secondary)
            Slider(value: $volume, in: 0...100, onEditingChanged: { editing in
                editingVolume = editing
                if editing {
                    editedOutputID = outputs?.selectedID
                } else {
                    guard let editedOutputID, (try? AudioOutputs.snapshot().selectedID) == editedOutputID else {
                        volumeError = true
                        volumeRevision += 1
                        return
                    }
                    let value = Int(volume.rounded())
                    isWritingVolume = true
                    volumeRevision += 1
                    Task {
                        do { try await system.setVolume(percent: value); volumeError = false }
                        catch { volumeError = true }
                        isWritingVolume = false
                    }
                }
            }) { Text("Volume") }
            .disabled(!volumeAvailable || isWritingVolume || isChangingOutput)
            if volumeError {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            }
            Text(volumeAvailable ? "\(Int(volume.rounded()))%" : "—")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.secondary).frame(width: 36, alignment: .trailing)
          }
          .help(volumeError ? Text("Could not change volume") : (volumeAvailable ? Text("Volume") : Text("Volume unavailable for this device")))
          HStack(spacing: 6) {
              Image(systemName: "hifispeaker")
                  .foregroundStyle(Theme.tertiary)
              Menu {
                  if let snapshot = outputs {
                      ForEach(snapshot.devices) { device in
                          Button {
                              isChangingOutput = true
                              volumeRevision += 1
                              let revision = volumeRevision
                              Task {
                                  do {
                                      let next = try await Task.detached {
                                          try AudioOutputs.select(device.id)
                                          return try AudioOutputs.snapshot()
                                      }.value
                                      outputs = next
                                      outputError = false
                                      selectionError = false
                                      let value = try? await system.outputVolume()
                                      if revision == volumeRevision && !editingVolume && !isWritingVolume {
                                          if let value { volume = Double(value) }
                                          volumeAvailable = value != nil
                                      }
                                  } catch { selectionError = true }
                                  isChangingOutput = false
                              }
                          } label: {
                              if device.id == snapshot.selectedID { Label(device.name, systemImage: "checkmark") }
                              else { Text(device.name) }
                          }
                      }
                  }
              } label: {
                  HStack(spacing: 4) {
                      Text(outputs?.devices.first(where: { $0.id == outputs?.selectedID })?.name ?? String(localized: "Audio output unavailable"))
                          .lineLimit(1)
                      Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                  }
                  .font(.system(size: 11.5, weight: .medium))
                  .foregroundStyle(Theme.secondary)
                  .frame(maxWidth: 240, alignment: .leading)
              }
              .menuStyle(.borderlessButton)
              .disabled(outputs?.devices.isEmpty != false || editingVolume || isWritingVolume || isChangingOutput)
              .help(Text("Audio output"))
              if outputError || selectionError {
                  Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                      .help(Text("Could not update audio output"))
              }
              Spacer(minLength: 0)
          }
        }
    }

    @ViewBuilder
    private var playerButton: some View {
        let preferred = app.preferences.playerBundleID
        HStack(spacing: 8) {
            if let name = MediaModel.appName(bundleID: preferred), app.media.nowPlaying?.appBundleIdentifier != preferred {
                if preferred == YandexMusicControl.bundleID {
                    Button { app.media.playPreferredPlayer(bundleID: preferred) } label: {
                        Label("Play \(name)", systemImage: "play.fill")
                    }
                    .buttonStyle(CapsuleButtonStyle())
                    .disabled(app.media.isStartingPlayer)
                } else {
                    Button { app.media.openPlayer(bundleID: preferred) } label: {
                        Label("Open \(name)", systemImage: "arrow.up.forward.app")
                    }.buttonStyle(CapsuleButtonStyle())
                }
            }
            Button("Choose your player…") { app.settingsPage = .music; app.openSettings() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
        }
    }
}
