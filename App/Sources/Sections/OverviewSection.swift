import PolkaCore
import PolkaSystem
import SwiftUI

struct OverviewSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 12) {
            if !app.preferences.hasSeenWelcome {
                WelcomeBanner()
            }
            HStack(spacing: 12) {
                MediaCard()
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1.4)
                VPNCard()
                NextEventCard()
            }
            .frame(maxHeight: .infinity)
            ScenariosRow()
                .frame(height: 92)
        }
    }
}

private struct WelcomeBanner: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.wave.fill").foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to Polka").font(.system(size: 13, weight: .semibold))
                Text("Point at the notch to open it, move away to close. ⌥⇧K opens it from the keyboard, ⌥⇧S saves the current browser tab.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            Button("Got it") {
                app.preferences.hasSeenWelcome = true
                app.panel.collapse()
            }
            .buttonStyle(CapsuleButtonStyle(prominent: true))
        }
        .padding(12)
        .background(Theme.card, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Cards

private struct MediaCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let media = app.media
        Card {
            HStack(alignment: .center, spacing: 14) {
                ArtworkView(size: 92, cornerRadius: 14)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        CardLabel("Music")
                        Spacer()
                        PlayingSource()
                    }
                    if let item = media.nowPlaying {
                        Text(item.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text(item.artist ?? "").font(.system(size: 12.5)).foregroundStyle(Theme.secondary).lineLimit(1)
                    } else {
                        Text("Nothing is playing").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        if let player = MediaModel.appName(bundleID: app.preferences.playerBundleID) {
                            Text("Press play to open \(player)")
                                .font(.system(size: 12.5)).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                    }
                    TransportControls(size: 30)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct VPNCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let vpn = app.vpn
        let active = vpn.active
        Card(highlight: active?.status == .connected ? Theme.active.opacity(0.7) : nil) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    CardLabel("VPN")
                    Spacer()
                    if let first = vpn.activeConnections.count <= 1 ? (active ?? vpn.connections.first) : nil {
                        Toggle(isOn: Binding(get: { active != nil }, set: { _ in Task { await vpn.toggle(first) } })) {
                            Text("VPN")
                        }
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(Theme.active)
                        .disabled(vpn.switching || first.status == .unknown)
                    }
                }
                Spacer(minLength: 8)
                (active != nil ? Text("VPN active") : (vpn.hasUnknownStatus ? Text("Status unknown") : Text("No active VPN")))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(active == nil ? Theme.warning : Theme.active)
                Text(active?.name ?? (vpn.connections.isEmpty ? String(localized: "No VPN set up") : String(localized: "No active VPN detected")))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let active, let since = vpn.connectedSince[active.id] {
                    Text(since, style: .timer)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                } else {
                    Button("Choose…") { app.panel.section = .vpn }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
        .frame(width: 190)
    }
}

private struct NextEventCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let agenda = app.agenda
        Card {
            VStack(alignment: .leading, spacing: 0) {
                CardLabel("Up next")
                Spacer(minLength: 8)
                if agenda.access != .granted {
                    Text("See your next meeting here")
                        .font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 8)
                    Button("Allow Calendar") { Task { await agenda.requestAccess() } }
                        .buttonStyle(CapsuleButtonStyle())
                } else if let next = agenda.next {
                    Text(Countdown.text(to: next.start, now: agenda.now))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(next.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    Text(next.start, format: .dateTime.hour().minute())
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                    Spacer(minLength: 8)
                    if next.meeting != nil {
                        Button {
                            agenda.join(next)
                        } label: {
                            Label("Join", systemImage: "video.fill")
                        }
                        .buttonStyle(CapsuleButtonStyle(prominent: true))
                    }
                } else {
                    Text("Nothing else today")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 8)
                }
            }
        }
        .frame(width: 200)
    }
}

enum Countdown {
    static func text(to date: Date, now: Date) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return String(localized: "Now") }
        if minutes < 60 { return String(localized: "In \(minutes) min") }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? String(localized: "In \(hours) h") : String(localized: "In \(hours) h \(rest) min")
    }
}

// MARK: - Scenarios

private struct ScenariosRow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let scenarios = Array(app.preferences.scenarios.prefix(4))
        if scenarios.isEmpty {
            Button {
                app.settingsPage = .scenarios
                app.openSettings()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles").font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Create a scenario").font(.system(size: 13.5, weight: .semibold))
                        Text("One click to switch VPN, music and tabs together — for work, calls or the evening.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.card, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 12) {
                ForEach(scenarios) { scenario in
                    ScenarioButton(scenario: scenario)
                }
            }
        }
    }
}

private struct ScenarioButton: View {
    @Environment(AppModel.self) private var app
    let scenario: Scenario

    var body: some View {
        let running = app.runningScenarioID == scenario.id
        Button {
            app.run(scenario)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: scenario.symbol).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if running { ProgressView().controlSize(.small) }
                }
                Spacer(minLength: 0)
                Text(scenario.name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                Text(ScenarioSummary.text(for: scenario, app: app))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
            .hoverHighlight(cornerRadius: Theme.cornerRadius)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(app.runningScenarioID != nil)
    }
}

enum ScenarioSummary {
    @MainActor
    static func text(for scenario: Scenario, app: AppModel) -> String {
        scenario.actions.map { action -> String in
            switch action {
            case .vpn(nil): String(localized: "VPN off")
            case .vpn(let id?): app.vpn.connections.first { $0.id == id }?.name ?? String(localized: "VPN")
            case .media(.play): String(localized: "Music on")
            case .media(.pause): String(localized: "Music off")
            case .openTabGroup(let id): app.tabs.library.group(id)?.name ?? String(localized: "Tabs")
            case .runShortcut(let name): name
            case .openURL(let url): url.host(percentEncoded: false) ?? url.absoluteString
            case .openApp(let id): appName(id)
            case .quitApp(let id): String(localized: "Quit \(appName(id))")
            case .appearance(.dark): String(localized: "Dark")
            case .appearance(.light): String(localized: "Light")
            case .appearance(.toggle): String(localized: "Switch appearance")
            case .volume(let percent): String(localized: "Volume \(percent)%")
            case .mute(true): String(localized: "Mute")
            case .mute(false): String(localized: "Unmute")
            }
        }
        .joined(separator: " · ")
    }

    @MainActor
    private static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path(percentEncoded: false)).replacingOccurrences(of: ".app", with: "")
    }
}
