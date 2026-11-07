import PolkaCore
import UniformTypeIdentifiers
import SwiftUI

struct VPNSection: View {
    @Environment(AppModel.self) private var app

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 12)]

    var body: some View {
        let vpn = app.vpn
        if !vpn.hasLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vpn.connections.isEmpty && !vpn.systemStatusUnavailable {
            VStack(spacing: 14) {
                Placeholder(
                    symbol: "lock.shield",
                    title: "No VPN connections found",
                    message:
                        "Polka controls VPNs registered in System Settings › VPN and proxy apps such as FSNT Client. If your client doesn’t appear, connect once in it, or add the app."
                )
                Button("Add VPN App…") { VPNAppPicker.run(app) }
                    .buttonStyle(CapsuleButtonStyle())
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(vpn.connections) { connection in
                            ConnectionTile(connection: connection)
                        }
                    }
                }
                .scrollIndicators(.never)
                if let error = vpn.lastError {
                    ScrollView(.vertical) {
                        Text(error)
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 40, maxHeight: 72)
                    .scrollIndicators(.visible)
                    .padding(10)
                    .background(Theme.card, in: .rect(cornerRadius: 12))
                }
                footer
                Text("Multiple VPNs may conflict. Their routes and DNS settings determine which traffic uses each connection.")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    private var footer: some View {
        let vpn = app.vpn
        return HStack(spacing: 10) {
            Circle()
                .fill(vpn.active == nil ? Theme.warning : Theme.active)
                .frame(width: 8, height: 8)
            if !vpn.activeConnections.isEmpty {
                Text("Active VPNs: \(vpn.activeConnections.count)")
            } else if vpn.hasUnknownStatus {
                Text("VPN status is unknown")
            } else {
                Text("No active VPN detected")
            }
            Spacer()

            Button {
                VPNAppPicker.run(app)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(IconButtonStyle(size: 26))
            .help(Text("Add a VPN app that is not listed, such as a proxy client"))
            if vpn.active != nil {
                Button("Disconnect known VPNs") { Task { await vpn.setActive(nil) } }
                    .buttonStyle(CapsuleButtonStyle())
                    .disabled(vpn.switching)
            }
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Theme.card, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

private struct ConnectionTile: View {
    @Environment(AppModel.self) private var app
    let connection: VPNConnection

    var body: some View {
        let vpn = app.vpn
        let isOn = connection.status.isActive
        let isBusy = vpn.busy.contains(connection.id)
        let appURL = vpn.providerApp(for: connection)

        Card(highlight: connection.status == .connected ? Theme.active : nil) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    AppIcon(url: appURL)
                    Spacer()
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else if connection.isTunnelblick, connection.status == .unknown, vpn.tunnelblickAccessDenied {
                        Button("Allow access…") { SystemSettings.open(.automation) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accent)
                            .help(Text("Allow Polka to control Tunnelblick in Automation settings."))
                    } else if connection.isAppManaged, connection.status == .unknown {
                        if connection.providerBundleID?.lowercased() == "moe.throne.macosx" {
                            Button("Set up FSNT…") { FSNTSetupWindow.show(app) }
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.accent)
                        } else if let appURL {
                            Button("Open App") { NSWorkspace.shared.open(appURL) }
                                .buttonStyle(.plain)
                        }
                    } else {
                        Toggle(isOn: Binding(get: { isOn }, set: { _ in Task { await vpn.toggle(connection) } })) {
                            Text(connection.name)
                        }
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(Theme.active)
                        .disabled(vpn.switching || connection.status == .unknown || connection.status == .disconnecting)
                    }
                }
                Text(connection.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                HStack {
                    status
                    Spacer()
                    if let appURL {
                        Button("Open App") { NSWorkspace.shared.open(appURL) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
        .frame(height: 132)
        .animation(.easeOut(duration: 0.2), value: connection.status)
    }

    @ViewBuilder
    private var status: some View {
        let vpn = app.vpn
        Group {
            switch connection.status {
            case .connected:
                if let since = vpn.connectedSince[connection.id] {
                    Text("Connected · \(Text(since, style: .timer))")
                } else {
                    Text("Connected")
                }
            case .connecting: Text("Connecting…")
            case .disconnecting: Text("Disconnecting…")
            case .invalid: Text("Configuration is invalid")
            case .unknown: Text("Status unavailable")
            case .disconnected:
                if connection.isAppManaged, let id = connection.providerBundleID, vpn.runningApps.contains(id) {
                    Text("Open, not connected")
                } else {
                    Text("Off")
                }
            }
        }
        .font(.system(size: 12.5, weight: .medium).monospacedDigit())
        .foregroundStyle(connection.status == .connected ? Theme.active : Theme.secondary)
    }
}

private struct AppIcon: View {
    let url: URL?

    var body: some View {
        if let url {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 38, height: 38)
        } else {
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 18))
                .frame(width: 38, height: 38)
                .background(Theme.cardHover, in: .rect(cornerRadius: 10, style: .continuous))
        }
    }
}

/// Lets the user point Polka at a VPN client it does not recognize.
@MainActor
enum VPNAppPicker {
    static func run(_ app: AppModel) {
        // The notch panel floats above everything, including this sheet.
        app.panel.collapse()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Add")
        panel.message = String(localized: "Choose a VPN app. Its connection must be controlled in the app.")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !app.vpn.addApp(at: url) {
            NSSound.beep()
        }
    }
}
