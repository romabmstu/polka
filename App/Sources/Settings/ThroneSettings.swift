import AppKit
import PolkaSystem
import SwiftUI

/// Connects Polka to FSNT Client, a build of Throne, through the client's
/// local API. Shown as a page in Settings and in its own window from the VPN
/// tile. The steps name the menus and buttons as FSNT shows them.
struct ThroneSettings: View {
    @Environment(AppModel.self) private var app
    @State private var key = ""
    @State private var portText = "9095"
    @State private var testing = false
    @State private var outcome: Outcome?

    private enum Outcome {
        case connected, badKey, failed, notRemoved
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                summary
                SetupStep(number: 1, title: "Open the integration settings in FSNT") {
                    StepText("In the FSNT menu bar at the top of the screen, choose:")
                    MenuPath(items: ["Preferences", "Integration Settings", "Throne API"])
                    Button("Open FSNT", action: openClient)
                    StepText(
                        "No Preferences menu? FSNT is showing its simple interface. Switch it to the advanced one first.",
                        size: 11.5)
                }
                SetupStep(number: 2, title: "Turn on the API and copy the key") {
                    CheckLine("Tick “Enable Throne API”.")
                    CheckLine("Leave “Listen” on “This computer only” and the port on 9095.")
                    CheckLine("Press “Copy” under the key, then “OK”.")
                }
                SetupStep(number: 3, title: "Paste the key into Polka") {
                    HStack(spacing: 8) {
                        SecureField("API key", text: $key)
                            .textContentType(.password)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(connect)
                        Button("Paste", action: paste)
                    }
                    HStack(spacing: 8) {
                        Text("Port").foregroundStyle(.secondary)
                        TextField("Port", text: $portText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 76)
                        Spacer()
                        if testing { ProgressView().controlSize(.small) }
                        Button("Connect", action: connect)
                            .buttonStyle(.borderedProminent)
                            .disabled(key.isEmpty || testing)
                    }
                    if let outcome { message(for: outcome) }
                }
                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { portText = String(app.vpn.thronePort) }
    }

    // MARK: Parts

    private var summary: some View {
        let connected = app.vpn.throneConfigured
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: connected ? "checkmark.circle.fill" : "bolt.horizontal.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(connected ? Color.green : Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                (connected ? Text("FSNT is connected") : Text("FSNT is not connected yet"))
                    .font(.system(size: 15, weight: .semibold))
                StepText(
                    connected
                        ? "Polka shows whether FSNT is on and switches it from the VPN section."
                        : "Three steps, about a minute. After that Polka shows whether FSNT is on and switches it for you.")
            }
        }
        .padding(.bottom, 4)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            StepText(
                "The key gives full control of FSNT, so do not share it. Polka keeps it in macOS Keychain and only talks to FSNT on this Mac.",
                size: 11.5)
            if app.vpn.throneConfigured {
                Button("Remove integration", role: .destructive, action: remove)
                    .disabled(testing)
            }
        }
        .padding(.top, 2)
    }

    private func message(for outcome: Outcome) -> some View {
        let good = outcome == .connected
        let text: LocalizedStringKey =
            switch outcome {
            case .connected: "Connected. You can close this window."
            case .badKey: "This does not look like an FSNT key. Press “Copy” in FSNT again, then “Paste” here."
            case .failed:
                "FSNT did not accept the connection. Check that FSNT is running, “Enable Throne API” is ticked and you pressed “OK”, then copy the key again."
            case .notRemoved: "Could not remove the key from Keychain."
            }
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: good ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(good ? Color.green : Color.orange)
            Text(text)
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    // MARK: Actions

    private func openClient() {
        let id = app.vpn.configuredApps.first { $0.bundleID.lowercased() == "moe.throne.macosx" }?.bundleID ?? "moe.Throne.macosx"
        if let url = app.vpn.appURL(for: id) ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.open(url)
        }
    }

    private func paste() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        key = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func connect() {
        guard !key.isEmpty, !testing else { return }
        testing = true
        outcome = nil
        Task {
            do {
                guard let port = UInt16(portText.trimmingCharacters(in: .whitespaces)), port > 0 else {
                    throw ThroneClient.Failure.connection
                }
                try await app.vpn.configureThrone(key: key, port: port)
                key = ""
                outcome = .connected
            } catch ThroneClient.Failure.invalidKey {
                outcome = .badKey
            } catch {
                outcome = .failed
            }
            testing = false
        }
    }

    private func remove() {
        do {
            try app.vpn.removeThrone()
            outcome = nil
        } catch {
            outcome = .notRemoved
        }
    }
}

/// One numbered step in a card of its own.
private struct SetupStep<Content: View>: View {
    let number: Int
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .frame(width: 26, height: 26)
                .background(Color.accentColor, in: .circle)
            VStack(alignment: .leading, spacing: 9) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minHeight: 26)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08))
        }
    }
}

private struct StepText: View {
    let text: LocalizedStringKey
    let size: CGFloat

    init(_ text: LocalizedStringKey, size: CGFloat = 12.5) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.system(size: size))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CheckLine: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A menu path drawn the way it is clicked through: Preferences › Integration Settings.
private struct MenuPath: View {
    let items: [LocalizedStringKey]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                Text(item)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Color.primary.opacity(0.09), in: .rect(cornerRadius: 6, style: .continuous))
            }
        }
    }
}
