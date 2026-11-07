import PolkaCore
import SwiftUI

/// Editable form of a scenario: one optional choice per kind of action.
struct ScenarioDraft: Equatable {
    enum VPNChoice: Hashable { case unchanged, off, connect(String) }
    enum MediaChoice: Hashable { case unchanged, play, pause }

    var name = ""
    var symbol = "sparkles"
    var vpn: VPNChoice = .unchanged
    var media: MediaChoice = .unchanged
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
            }
        }
    }

    func scenario(id: UUID) -> Scenario {
        var actions: [Scenario.Action] = []
        switch vpn {
        case .unchanged: break
        case .off: actions.append(.vpn(serviceID: nil))
        case .connect(let id): actions.append(.vpn(serviceID: id))
        }
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
                Text("Scenarios run several actions at once — connect a VPN, start music, open a group of tabs or run a shortcut from the Shortcuts app.")
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
