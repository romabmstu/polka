import AppKit
import PolkaCore
import SwiftUI
import UniformTypeIdentifiers

/// Editable form of a scenario: one optional choice per kind of action.
struct ScenarioDraft: Equatable {
    enum VPNChoice: Hashable { case unchanged, off, connect(String) }
    enum MediaChoice: Hashable { case unchanged, play, pause }
    enum AppearanceChoice: Hashable { case unchanged, dark, light, toggle }
    enum SoundChoice: Hashable { case unchanged, mute, unmute, level }

    var name = ""
    var symbol = "sparkles"
    var vpn: VPNChoice = .unchanged
    var media: MediaChoice = .unchanged
    var appearance: AppearanceChoice = .unchanged
    var sound: SoundChoice = .unchanged
    var volume: Double = 50
    var appsToOpen: [String] = []
    var appsToQuit: [String] = []
    var tabGroup: UUID?
    var shortcut = ""
    var link = ""

    init() {}

    init(_ scenario: Scenario) {
        name = scenario.name
        symbol = scenario.symbol
        for action in scenario.actions {
            switch action {
            case .vpn(nil): vpn = .off
            case .vpn(let id?): vpn = .connect(id)
            case .media(.play): media = .play
            case .media(.pause): media = .pause
            case .openTabGroup(let id): tabGroup = id
            case .runShortcut(let name): shortcut = name
            case .openURL(let url): link = url.absoluteString
            case .openApp(let id): appsToOpen.append(id)
            case .quitApp(let id): appsToQuit.append(id)
            case .appearance(.dark): appearance = .dark
            case .appearance(.light): appearance = .light
            case .appearance(.toggle): appearance = .toggle
            case .volume(let percent):
                sound = .level
                volume = Double(percent)
            case .mute(let muted): sound = muted ? .mute : .unmute
            }
        }
    }

    /// Actions in the order they make sense: close distractions, switch the
    /// network and the look of the system, then open things.
    func scenario(id: UUID) -> Scenario {
        var actions: [Scenario.Action] = appsToQuit.filter(Scenario.isValidBundleID).map { .quitApp(bundleID: $0) }
        switch vpn {
        case .unchanged: break
        case .off: actions.append(.vpn(serviceID: nil))
        case .connect(let id): actions.append(.vpn(serviceID: id))
        }
        switch appearance {
        case .unchanged: break
        case .dark: actions.append(.appearance(.dark))
        case .light: actions.append(.appearance(.light))
        case .toggle: actions.append(.appearance(.toggle))
        }
        switch sound {
        case .unchanged: break
        case .mute: actions.append(.mute(true))
        case .unmute: actions.append(.mute(false))
        case .level: actions.append(.volume(Scenario.clampedVolume(Int(volume.rounded()))))
        }
        actions += appsToOpen.filter(Scenario.isValidBundleID).map { .openApp(bundleID: $0) }
        switch media {
        case .unchanged: break
        case .play: actions.append(.media(.play))
        case .pause: actions.append(.media(.pause))
        }
        if let tabGroup { actions.append(.openTabGroup(tabGroup)) }
        if Scenario.isValidShortcutName(shortcut) { actions.append(.runShortcut(name: shortcut)) }
        if let url = URLNormalizer.url(fromUserInput: link) { actions.append(.openURL(url)) }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Scenario(id: id, name: trimmed.isEmpty ? String(localized: "Scenario") : trimmed, symbol: symbol, actions: actions)
    }
}

struct ScenariosSettings: View {
    @Environment(AppModel.self) private var app
    @State private var selection: Scenario.ID?

    var body: some View {
        let preferences = app.preferences
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(preferences.scenarios) { scenario in
                        Label(scenario.name, systemImage: scenario.symbol).tag(scenario.id)
                    }
                    .onMove { preferences.scenarios.move(fromOffsets: $0, toOffset: $1) }
                }
                Divider()
                HStack(spacing: 0) {
                    Button {
                        let scenario = ScenarioDraft().scenario(id: UUID())
                        preferences.scenarios.append(scenario)
                        selection = scenario.id
                    } label: {
                        Image(systemName: "plus").frame(width: 24, height: 22)
                    }
                    .accessibilityLabel(Text("Add Scenario"))
                    Button {
                        preferences.scenarios.removeAll { $0.id == selection }
                        selection = preferences.scenarios.first?.id
                    } label: {
                        Image(systemName: "minus").frame(width: 24, height: 22)
                    }
                    .disabled(selection == nil)
                    .accessibilityLabel(Text("Remove Scenario"))
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(4)
            }
            .frame(width: 180)

            Divider()

            if let id = selection, let scenario = preferences.scenarios.first(where: { $0.id == id }) {
                ScenarioEditor(id: id, draft: ScenarioDraft(scenario))
                    .id(id)
            } else {
                Text("Scenarios run several actions at once — connect a VPN, switch to dark mode, set the volume, open or quit apps, start music, open a group of tabs or run a shortcut.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { selection = selection ?? preferences.scenarios.first?.id }
    }
}

private struct ScenarioEditor: View {
    @Environment(AppModel.self) private var app
    let id: UUID
    @State var draft: ScenarioDraft
    @State private var shortcuts: [String] = []

    private static let symbols = [
        "sparkles", "briefcase.fill", "phone.fill", "moon.fill", "headphones", "house.fill",
        "cup.and.saucer.fill", "airplane", "book.fill", "figure.run",
    ]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
                Picker("Icon", selection: $draft.symbol) {
                    ForEach(Self.symbols, id: \.self) { Image(systemName: $0).tag($0) }
                }
            }
            Section("When it runs") {
                Picker("VPN", selection: $draft.vpn) {
                    Text("Don’t change").tag(ScenarioDraft.VPNChoice.unchanged)
                    Text("Turn off").tag(ScenarioDraft.VPNChoice.off)
                    ForEach(app.vpn.connections) { connection in
                        Text(connection.name).tag(ScenarioDraft.VPNChoice.connect(connection.id))
                    }
                }
                Picker("Appearance", selection: $draft.appearance) {
                    Text("Don’t change").tag(ScenarioDraft.AppearanceChoice.unchanged)
                    Text("Dark").tag(ScenarioDraft.AppearanceChoice.dark)
                    Text("Light").tag(ScenarioDraft.AppearanceChoice.light)
                    Text("Switch").tag(ScenarioDraft.AppearanceChoice.toggle)
                }
                Picker("Sound", selection: $draft.sound) {
                    Text("Don’t change").tag(ScenarioDraft.SoundChoice.unchanged)
                    Text("Mute").tag(ScenarioDraft.SoundChoice.mute)
                    Text("Unmute").tag(ScenarioDraft.SoundChoice.unmute)
                    Text("Set volume").tag(ScenarioDraft.SoundChoice.level)
                }
                if draft.sound == .level {
                    Slider(value: $draft.volume, in: 0...100, step: 5) {
                        Text("Volume \(Int(draft.volume))%")
                    }
                }
                Picker("Music", selection: $draft.media) {
                    Text("Don’t change").tag(ScenarioDraft.MediaChoice.unchanged)
                    Text("Play").tag(ScenarioDraft.MediaChoice.play)
                    Text("Pause").tag(ScenarioDraft.MediaChoice.pause)
                }
                Picker("Open tabs", selection: $draft.tabGroup) {
                    Text("None").tag(UUID?.none)
                    ForEach(app.tabs.library.orderedGroups) { group in
                        Text(group.name).tag(UUID?.some(group.id))
                    }
                }
                Picker("Run shortcut", selection: $draft.shortcut) {
                    Text("None").tag("")
                    ForEach(shortcutChoices, id: \.self) { Text($0).tag($0) }
                }
                TextField("Open link", text: $draft.link, prompt: Text("meet.google.com/…"))
            }
            Section {
                AppList(title: "Open apps", bundleIDs: $draft.appsToOpen)
                AppList(title: "Quit apps", bundleIDs: $draft.appsToQuit)
            } footer: {
                Text("To switch a Focus mode, make a shortcut with the “Set Focus” action in the Shortcuts app and pick it above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { shortcuts = await app.availableShortcuts() }
        .onChange(of: draft) { _, new in
            guard let index = app.preferences.scenarios.firstIndex(where: { $0.id == id }) else { return }
            app.preferences.scenarios[index] = new.scenario(id: id)
        }
    }

    /// Keeps the saved shortcut selectable even before the list has loaded.
    private var shortcutChoices: [String] {
        draft.shortcut.isEmpty || shortcuts.contains(draft.shortcut) ? shortcuts : [draft.shortcut] + shortcuts
    }
}

/// Apps a scenario opens or quits, picked from the Applications folder.
private struct AppList: View {
    let title: LocalizedStringKey
    @Binding var bundleIDs: [String]

    var body: some View {
        LabeledContent(title) {
            Button("Add…", action: add)
        }
        ForEach(bundleIDs, id: \.self) { id in
            HStack(spacing: 8) {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(FileManager.default.displayName(atPath: url.path(percentEncoded: false)).replacingOccurrences(of: ".app", with: ""))
                } else {
                    Image(systemName: "questionmark.app").frame(width: 18, height: 18)
                    Text(id).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    bundleIDs.removeAll { $0 == id }
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Remove"))
            }
            .padding(.leading, 12)
        }
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, Scenario.isValidBundleID(id),
                id != Bundle.main.bundleIdentifier, !bundleIDs.contains(id)
            else { continue }
            bundleIDs.append(id)
        }
    }
}
