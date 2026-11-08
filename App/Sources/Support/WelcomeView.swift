import AppKit
import PolkaSystem
import SwiftUI

/// First-run window: what Polka is, the permissions it may need with their
/// live status, starting at login, and the shortcuts. Everything is optional
/// and can be changed later in Settings.
struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    let permissions: PermissionsModel
    /// `true` when the user wants to see the panel right away.
    let onFinish: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section {
                    ForEach(permissions.browsers) { status in
                        browserRow(status)
                    }
                    PermissionRowView(
                        icon: .symbol("calendar", .red),
                        title: Text("Calendars", tableName: "Support"),
                        detail: Text("Today’s events and the next meeting. Read-only.", tableName: "Support"),
                        state: permissions.calendars,
                        isBusy: false,
                        action: actionLabel(for: permissions.calendars)
                    ) {
                        Task { await permissions.requestCalendars(using: app.agenda) }
                    }
                    PermissionRowView(
                        icon: .symbol("accessibility", .blue),
                        title: Text("Accessibility", tableName: "Support"),
                        detail: Text("Optional: ⌥⇧T translates the text you select in any app.", tableName: "Support"),
                        state: permissions.accessibility ? .granted : .notAsked,
                        isBusy: false,
                        action: permissions.accessibility ? nil : Text("Open Settings", tableName: "Support")
                    ) {
                        permissions.requestAccessibility()
                    }
                } header: {
                    Text("Permissions", tableName: "Support")
                } footer: {
                    Text("Polka asks only for what a feature needs, and everything stays on your Mac. You can change these any time in System Settings › Privacy & Security.", tableName: "Support")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle(isOn: Binding(get: { permissions.launchAtLogin }, set: { permissions.setLaunchAtLogin($0) })) {
                        Text("Open Polka at login", tableName: "Support")
                    }
                    if let error = permissions.launchAtLoginError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Start", tableName: "Support")
                }

                Section {
                    shortcut("⌥⇧K", Text("Open or close the panel", tableName: "Support"))
                    shortcut("⌥⇧S", Text("Save the current browser tab", tableName: "Support"))
                    shortcut("⌥⇧T", Text("Translate the selected text", tableName: "Support"))
                } header: {
                    Text("Shortcuts", tableName: "Support")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            HStack {
                Button {
                    onFinish(false)
                } label: {
                    Text("Done", tableName: "Support")
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    onFinish(true)
                } label: {
                    Text("Show Me the Panel", tableName: "Support")
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(16)
        }
        .frame(width: 560, height: 700)
        .task {
            // Settings can change behind Polka's back; keep the list honest.
            while !Task.isCancelled {
                permissions.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
            Text("Welcome to Polka", tableName: "Support")
                .font(.system(size: 24, weight: .bold))
            Text("Point at the notch to open the panel, move away to close it. On a display without a notch, use the small capsule in the menu bar.", tableName: "Support")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .padding(.top, 28)
        .padding(.bottom, 4)
    }

    private func browserRow(_ status: PermissionsModel.BrowserStatus) -> some View {
        PermissionRowView(
            icon: .app(status.appURL),
            title: Text(status.browser.name),
            detail: Text("Save its tabs with ⌥⇧S and open saved groups.", tableName: "Support"),
            state: status.state,
            isBusy: permissions.busy.contains(status.browser.bundleIdentifier),
            action: status.state == .needsApp
                ? Text("Open and Allow", tableName: "Support")
                : actionLabel(for: status.state)
        ) {
            Task { await permissions.request(status) }
        }
    }

    private func actionLabel(for state: PermissionsModel.State) -> Text? {
        switch state {
        case .granted: nil
        case .denied: Text("Open Settings", tableName: "Support")
        case .notAsked, .needsApp, .unknown: Text("Allow", tableName: "Support")
        }
    }

    private func shortcut(_ keys: String, _ title: Text) -> some View {
        LabeledContent {
            Text(keys).font(.system(.body, design: .rounded).weight(.semibold)).monospaced()
        } label: {
            title
        }
    }
}

private struct PermissionRowView: View {
    enum Icon {
        case app(URL)
        case symbol(String, Color)
    }

    let icon: Icon
    let title: Text
    let detail: Text
    let state: PermissionsModel.State
    let isBusy: Bool
    let action: Text?
    let perform: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            iconView
            VStack(alignment: .leading, spacing: 2) {
                title.font(.system(size: 13, weight: .semibold))
                detail.font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isBusy {
                ProgressView().controlSize(.small)
            } else if state == .granted {
                Label {
                    Text("Allowed", tableName: "Support")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .foregroundStyle(.green)
                .font(.system(size: 12.5, weight: .medium))
            } else if let action {
                VStack(alignment: .trailing, spacing: 3) {
                    Button(action: perform) { action }
                    if state == .denied {
                        Text("Turned off in System Settings", tableName: "Support")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .app(let url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 28, height: 28)
        case .symbol(let name, let color):
            Image(systemName: name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color.gradient, in: .rect(cornerRadius: 7, style: .continuous))
        }
    }
}
