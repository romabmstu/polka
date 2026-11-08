import PolkaCore
import PolkaSystem
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, music, fsnt, sections, scenarios, privacy, updates, about
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .music: "Music"
        case .fsnt: "FSNT / Throne"
        case .sections: "Sections"
        case .scenarios: "Scenarios"
        case .privacy: "Privacy"
        case .updates: "Updates"
        case .about: "About"
        }
    }
    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .music: "music.note"
        case .fsnt: "network"
        case .sections: "square.grid.2x2"
        case .scenarios: "sparkles"
        case .privacy: "hand.raised"
        case .updates: "arrow.down.circle"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Polka").font(.system(size: 21, weight: .bold)).padding(.horizontal, 14).padding(.vertical, 18)
                ForEach(SettingsPage.allCases) { page in
                    Button { app.settingsPage = page } label: {
                        Label(page.title, systemImage: page.symbol)
                            .font(.system(size: 13, weight: app.settingsPage == page ? .semibold : .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).frame(height: 38)
                            .background(app.settingsPage == page ? Color.accentColor.opacity(0.20) : .clear, in: .rect(cornerRadius: 10))
                            .contentShape(.rect)
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(12).frame(width: 190).background(Color.primary.opacity(0.035))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(app.settingsPage.title).font(.system(size: 22, weight: .bold))
                    .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 10)
                settingsContent.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 720, minHeight: 560)
    }
    @ViewBuilder private var settingsContent: some View {
        switch app.settingsPage {
        case .general: GeneralSettings()
        case .music: MusicSettings()
        case .fsnt: ThroneSettings()
        case .sections: SectionsSettings()
        case .scenarios: ScenariosSettings()
        case .privacy: PrivacySettings()
        case .updates: UpdatesSettings()
        case .about: AboutSettings()
        }
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
                    Text("Display with the pointer").tag(DisplayChoice.pointer)
                    Text("Built-in display").tag(DisplayChoice.builtIn)
                    Text("Main display").tag(DisplayChoice.main)
                }
                Toggle("Close after opening a saved tab", isOn: $preferences.closeAfterOpeningTab)
                Toggle("Ask where to save with ⌥⇧S", isOn: $preferences.askWhereToSave)
            } footer: {
                Text("On displays without a notch Polka is a capsule at the top center. Point at it or press ⌥⇧K.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("In the closed notch") {
                Toggle("What’s playing", isOn: $preferences.showMusicIndicator)
                Toggle("VPN status", isOn: $preferences.showVPNIndicator)
                Toggle("Countdown to the next meeting", isOn: $preferences.showMeetingCountdown)
                Picker("Start the countdown", selection: $preferences.meetingLeadMinutes) {
                    Text("10 minutes before").tag(10)
                    Text("15 minutes before").tag(15)
                    Text("30 minutes before").tag(30)
                    Text("1 hour before").tag(60)
                }
                .disabled(!preferences.showMeetingCountdown)
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
                LabeledContent("Save the current browser tab") { Text("⌥⇧S").monospaced() }
                LabeledContent("Switch sections") { Text("⌘1 … ⌘9").monospaced() }
            }

            Section {
                ForEach(app.vpn.configuredApps) { vpnApp in
                    LabeledContent(vpnApp.name) {
                        if app.preferences.vpnApps.contains(where: { $0.bundleID == vpnApp.bundleID }) {
                            Button("Remove") { app.vpn.removeApp(vpnApp.bundleID) }
                        } else {
                            Text("Found automatically").foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Add VPN App…") { VPNAppPicker.run(app) }
            } header: {
                Text("VPN apps")
            } footer: {
                Text("For clients that don’t appear in System Settings › VPN. Polka can open the app, but its connection must be controlled in the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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


}

private struct MusicSettings: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        Form {
            Section {
                LabeledContent("Player") {
                    HStack {
                        Text(MediaModel.appName(bundleID: app.preferences.playerBundleID) ?? String(localized: "Not chosen"))
                            .foregroundStyle(.secondary)
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.application]
                            panel.directoryURL = URL(filePath: "/Applications")
                            panel.prompt = String(localized: "Choose")
                            guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
                            app.preferences.playerBundleID = id
                        }
                        if !app.preferences.playerBundleID.isEmpty {
                            Button("Clear") { app.preferences.playerBundleID = "" }
                        }
                    }
                }
            } footer: {
                Text("When nothing is playing, Play starts Yandex Music or opens another selected player. The controls otherwise follow the current source.")
            }
        }.formStyle(.grouped)
    }
}

// MARK: - Sections

private struct SectionsSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let preferences = app.preferences
        Form {
            Section {
                List {
                    ForEach(preferences.sections) { section in
                        Toggle(isOn: Binding(get: { true }, set: { preferences.setEnabled(section, $0) })) {
                            Label {
                                Text(section.title)
                            } icon: {
                                Image(systemName: section.symbol)
                            }
                        }
                        .disabled(section == .overview)
                    }
                    .onMove { preferences.sections.move(fromOffsets: $0, toOffset: $1) }
                }
                .frame(minHeight: 260)
            } header: {
                Text("Shown in the panel — drag to reorder")
            }
            let hidden = PanelSection.allCases.filter { !preferences.isEnabled($0) }
            if !hidden.isEmpty {
                Section("Hidden") {
                    ForEach(hidden) { section in
                        Toggle(isOn: Binding(get: { false }, set: { preferences.setEnabled(section, $0) })) {
                            Label {
                                Text(section.title)
                            } icon: {
                                Image(systemName: section.symbol)
                            }
                        }
                    }
                }
            }
            Section("Calendars") {
                CalendarChooser()
            }
        }
        .formStyle(.grouped)
    }
}

private struct CalendarChooser: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let calendars = app.agenda.calendars
        if calendars.isEmpty {
            Text("Allow Calendar access in the panel to choose calendars.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(calendars) { calendar in
                Toggle(isOn: Binding(
                    get: { !app.preferences.hiddenCalendarIDs.contains(calendar.id) },
                    set: { shown in
                        if shown { app.preferences.hiddenCalendarIDs.remove(calendar.id) }
                        else { app.preferences.hiddenCalendarIDs.insert(calendar.id) }
                        app.agenda.reload()
                    })
                ) {
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: calendar.colorHex ?? "") ?? .accentColor).frame(width: 10, height: 10)
                        Text(calendar.title)
                        Text(calendar.source).foregroundStyle(.secondary)
                    }
                }
            }
        }
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
                    title: "Browsers", detail: "Safari, Chrome, Arc and others: read and open tabs",
                    granted: app.tabs.hasBrowserAccess, pane: .automation)
                PermissionRow(
                    title: "Calendars", detail: "Today’s events", granted: app.agenda.access == .granted, pane: .calendars)
            }
        }
        .formStyle(.grouped)
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

// MARK: - Updates

private struct UpdatesSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var preferences = app.preferences
        let updates = app.updates
        Form {
            Section {
                LabeledContent("Installed version") { Text(updates.versionDescription).monospacedDigit() }
                Picker("Get", selection: $preferences.updateChannel) {
                    Text("Releases").tag(UpdateChannel.stable)
                    Text("Every new build (beta)").tag(UpdateChannel.beta)
                }
                .onChange(of: preferences.updateChannel) { _, channel in
                    Task { await updates.check(channel: channel) }
                }
                Toggle("Check automatically", isOn: $preferences.checkForUpdatesAutomatically)
                    .onChange(of: preferences.checkForUpdatesAutomatically) { _, _ in
                        updates.startAutomaticChecks(preferences: preferences)
                    }
            } footer: {
                Text("Updates come only from github.com/romabmstu/polka and are installed only if their signature matches the key built into Polka.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    switch updates.state {
                    case .checking:
                        ProgressView().controlSize(.small)
                        Text("Checking…")
                    case .upToDate:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Polka is up to date")
                    case .available, .downloading:
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
                        Text("An update is available")
                    case .failed:
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Update failed")
                    case .idle:
                        Text("Not checked yet").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check Now") { Task { await updates.check(channel: preferences.updateChannel) } }
                        .disabled(updates.state == .checking)
                }
                if updates.available != nil || updates.hasFailed {
                    UpdateDetails()
                }
                if let last = updates.lastChecked {
                    Text("Last checked \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
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
            Link(destination: URL(string: "https://romabmstu.github.io/polka/#support")!) {
                Label("Support Polka", systemImage: "heart.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
            Text("Free and open source under the MIT License.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}


struct ThroneSettings: View {
    @Environment(AppModel.self) private var app
    @State private var key = ""
    @State private var message: String?
    @State private var testing = false
    @State private var portText = "9095"

    var body: some View {
        Form {
            Section {
                Text("1. Open the client. In FSNT, look for Advanced mode under More; in Throne, choose Program → Advanced Mode.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open FSNT / Throne") {
                    if let item = app.vpn.configuredApps.first(where: { $0.bundleID.lowercased() == "moe.throne.macosx" }),
                       let url = app.vpn.appURL(for: item.bundleID) {
                        NSWorkspace.shared.open(url)
                    }
                }
                Text("2. In Preferences → Integration Settings → Throne API, enable the API on 127.0.0.1. Copy the API key and check its port.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("If your version has no advanced mode or Throne API, use Open App to control the VPN there; Polka cannot control it without the API.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("3. Enter the port and key below, then select Connect. The key gives full control of this client; do not share it.")
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Port", text: $portText)
                SecureField("API key", text: $key)
                    .textContentType(.password)
                HStack {
                    Button("Connect") {
                        testing = true
                        Task {
                            do {
                                guard let port = UInt16(portText), port > 0 else { throw ThroneClient.Failure.connection }
                                try await app.vpn.configureThrone(key: key, port: port)
                                key = ""
                                message = String(localized: "FSNT integration connected.")
                            } catch {
                                message = String(localized: "Could not connect. Check the API, key, and local address in FSNT.")
                            }
                            testing = false
                        }
                    }.disabled(key.isEmpty || testing)
                    if app.vpn.throneConfigured {
                        Button("Remove integration") {
                            do { try app.vpn.removeThrone(); message = nil }
                            catch { message = String(localized: "Could not remove the key from Keychain.") }
                        }.disabled(testing)
                    }
                    if testing { ProgressView().controlSize(.small) }
                }
                if let message { Text(message).font(.caption).fixedSize(horizontal: false, vertical: true) }
            } header: {
                Text("FSNT / Throne")
            } footer: {
                Text("The key is stored in macOS Keychain. Polka only connects to this Mac. Other VPN apps need their own integration.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
        .onAppear { portText = String(app.vpn.thronePort) }
    }
}
