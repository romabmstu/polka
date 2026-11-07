import PolkaCore
import PolkaSystem
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            SectionsSettings().tabItem { Label("Sections", systemImage: "square.grid.2x2") }
            ScenariosSettings().tabItem { Label("Scenarios", systemImage: "sparkles") }
            PrivacySettings().tabItem { Label("Privacy", systemImage: "hand.raised") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 460)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var app
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var preferences = app.preferences
        Form {
            Section {
                Toggle("Open when the pointer reaches the notch", isOn: $preferences.openOnHover)
                LabeledContent("Delay") {
                    Slider(value: $preferences.hoverDelay, in: 0...0.6, step: 0.05) {
                        Text("Delay")
                    } minimumValueLabel: {
                        Text("None")
                    } maximumValueLabel: {
                        Text("0.6 s")
                    }
                    .labelsHidden()
                }
                .disabled(!preferences.openOnHover)
                Picker("Show on", selection: $preferences.display) {
                    Text("Built-in display").tag(DisplayChoice.builtIn)
                    Text("Main display").tag(DisplayChoice.main)
                }
            }

            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Keyboard") {
                LabeledContent("Open or close Polka") { Text("⌥⇧K").monospaced() }
                LabeledContent("Save the current Safari tab") { Text("⌥⇧S").monospaced() }
                LabeledContent("Switch sections") { Text("⌘1 … ⌘8").monospaced() }
            }

            Section("Music") {
                LabeledContent("Player") {
                    HStack {
                        Text(MediaModel.playerName(bundleID: preferences.playerBundleID) ?? String(localized: "Not chosen"))
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: choosePlayer)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func choosePlayer() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        app.preferences.playerBundleID = id
    }
}

// MARK: - Sections

private struct SectionsSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let preferences = app.preferences
        Form {
            Section {
                ForEach(PanelSection.allCases) { section in
                    Toggle(isOn: Binding(get: { preferences.isEnabled(section) }, set: { preferences.setEnabled(section, $0) })) {
                        Label {
                            Text(section.title)
                        } icon: {
                            Image(systemName: section.symbol)
                        }
                    }
                    .disabled(section == .overview)
                }
            } footer: {
                Text("Hidden sections are removed from the panel. Overview is always shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var preferences = app.preferences
        Form {
            Section {
                Toggle("Remember copied text", isOn: $preferences.clipboardHistoryEnabled)
                    .onChange(of: preferences.clipboardHistoryEnabled) { _, on in app.clipboard.setEnabled(on) }
            } footer: {
                Text("Kept in memory and cleared on quit. Content that password managers mark as concealed is never read.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Download exchange rates", isOn: $preferences.exchangeRatesEnabled)
                CurrencyListField()
            } footer: {
                Text("The only network request Polka makes: open.er-api.com, a few times a day, with no personal data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Permissions") {
                PermissionRow(
                    title: "Safari", detail: "Read and open tabs", granted: app.tabs.safariState == .ready,
                    pane: .automation)
                PermissionRow(title: "Accessibility", detail: "Music keys", granted: app.media.isAllowed, pane: .accessibility)
                PermissionRow(
                    title: "Calendars", detail: "Today’s events", granted: app.agenda.access == .granted, pane: .calendars)
            }
        }
        .formStyle(.grouped)
        .onAppear { app.media.refreshPermission() }
    }
}

/// Edited as free text and applied when the user presses Return or leaves
/// the field, so partially typed codes are not thrown away.
private struct CurrencyListField: View {
    @Environment(AppModel.self) private var app
    @State private var text = ""

    var body: some View {
        TextField("Currencies", text: $text, prompt: Text("USD, EUR, RUB"))
            .onAppear { text = app.preferences.favoriteCurrencies.joined(separator: ", ") }
            .onSubmit(apply)
            .onDisappear(perform: apply)
    }

    private func apply() {
        let codes = text.uppercased().split { !$0.isLetter }.map(String.init).filter { $0.count == 3 }
        guard !codes.isEmpty else { return }
        var seen = Set<String>()
        app.preferences.favoriteCurrencies = Array(codes.filter { seen.insert($0).inserted }.prefix(6))
        if !app.preferences.favoriteCurrencies.contains(app.calculator.baseCurrency) {
            app.calculator.baseCurrency = app.preferences.favoriteCurrencies[0]
        }
        text = app.preferences.favoriteCurrencies.joined(separator: ", ")
    }
}

private struct PermissionRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let granted: Bool
    let pane: SystemSettings.Pane

    var body: some View {
        LabeledContent {
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Open Settings") { SystemSettings.open(pane) }
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

// MARK: - About

private struct AboutSettings: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Polka").font(.title.bold())
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("A control center that lives in your MacBook’s notch.")
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("Website", destination: URL(string: "https://romabmstu.github.io/polka/")!)
                Link("Source code", destination: URL(string: "https://github.com/romabmstu/polka")!)
                Link("Report a problem", destination: URL(string: "https://github.com/romabmstu/polka/issues/new/choose")!)
            }
            Text("Free and open source under the MIT License.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
