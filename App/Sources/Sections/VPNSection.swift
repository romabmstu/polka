import PolkaCore
import SwiftUI

struct VPNSection: View {
    @Environment(AppModel.self) private var app

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 12)]

    var body: some View {
        let vpn = app.vpn
        if !vpn.hasLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vpn.connections.isEmpty {
            Placeholder(
                symbol: "lock.shield",
                title: "No VPN connections found",
                message:
                    "Polka controls VPNs registered in System Settings › VPN. If your client doesn’t appear there, connect once in the client itself so it can add its configuration."
            )
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
                footer
            }
        }
    }

    private var footer: some View {
        let vpn = app.vpn
        return HStack(spacing: 10) {
            Circle()
                .fill(vpn.active == nil ? Theme.warning : Theme.active)
                .frame(width: 8, height: 8)
            if let error = vpn.lastError {
                Text(error).foregroundStyle(Theme.warning)
            } else if let active = vpn.active {
                Text("Traffic goes through \(active.name)")
            } else {
                Text("Your connection is not protected by a VPN")
            }
            Spacer()
            Text("Only one VPN stays on at a time").foregroundStyle(Theme.tertiary)
            if vpn.active != nil {
                Button("Disconnect") { Task { await vpn.setActive(nil) } }
                    .buttonStyle(CapsuleButtonStyle())
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
                    } else {
                        Toggle(isOn: Binding(get: { isOn }, set: { _ in Task { await vpn.toggle(connection) } })) {
                            Text(connection.name)
                        }
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(Theme.active)
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
            case .disconnected, .unknown: Text("Off")
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
