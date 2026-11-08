import SwiftUI

struct ExpandedPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let panel = app.panel
        VStack(alignment: .leading, spacing: 14) {
            if let request = panel.saveRequest {
                SavePicker(request: request)
                    .id(request.id)
                    .transition(.opacity)
            } else {
                header
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(.top, panel.hasNotch ? panel.notchHeight + 6 : 14)
        .padding(.horizontal, PanelMetrics.contentPadding + (panel.hasNotch ? 10 : 0))
        .padding(.bottom, PanelMetrics.contentPadding)
        .overlay(alignment: .bottom) { toast }
        .foregroundStyle(.white)
    }

    private var header: some View {
        let panel = app.panel
        let sections = app.preferences.sections
        return HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(Array(sections.enumerated()), id: \.element) { index, section in
                    SectionTab(section: section, isSelected: panel.section == section) {
                        panel.section = section
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.045), in: .capsule)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 0.7))
            Spacer(minLength: 0)
            if app.updates.available != nil {
                UpdateBadge()
            }
            Button {
                panel.togglePin()
            } label: {
                Image(systemName: panel.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(IconButtonStyle(size: 28))
            .foregroundStyle(panel.isPinned ? Theme.active : Theme.secondary)
            .help(panel.isPinned ? Text("Unpin") : Text("Keep open"))

            Menu {
                Button("Settings…") { app.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
                Button("Check for Updates…") {
                    Task { await app.updates.check(channel: app.preferences.updateChannel) }
                    app.settingsPage = .updates
                    app.openSettings()
                }
                Divider()
                Button("Quit Polka") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(.circle)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(Text("More"))
        }
        .frame(height: 36)
    }

    @ViewBuilder
    private var content: some View {
        switch app.panel.section {
        case .overview: OverviewSection()
        case .tabs: TabsSection()
        case .vpn: VPNSection()
        case .media: MediaSection()
        case .calendar: CalendarSection()
        case .calculator: CalculatorSection()
        case .clipboard: ClipboardSection()
        case .shelf: ShelfSection()
        case .translator: TranslatorSection()
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let flash = app.panel.flash {
            HStack(spacing: 8) {
                Image(systemName: flash.symbol)
                Text(flash.text).lineLimit(1)
                if app.tabs.canUndo, flash.canUndo {
                    Button("Undo") {
                        app.tabs.undo()
                        app.panel.dismissFlash()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(.white, in: .capsule)
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(flash.id)
        }
    }
}

private struct SectionTab: View {
    let section: PanelSection
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: section.symbol)
                    .font(.system(size: 12.5, weight: .semibold))
                if isSelected {
                    Text(section.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .foregroundStyle(isSelected ? Color.black : (isHovered ? Color.white : Theme.secondary))
            .background {
                if isSelected { Capsule().fill(Theme.selectionGradient) }
                else if isHovered { Capsule().fill(Theme.cardHover) }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isHovered)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isSelected)
        .help(Text(section.title))
        .accessibilityLabel(Text(section.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct UpdateBadge: View {
    @Environment(AppModel.self) private var app
    @State private var isShowingDetails = false

    var body: some View {
        Button {
            isShowingDetails = true
        } label: {
            Label("Update", systemImage: "arrow.down.circle.fill")
        }
        .buttonStyle(CapsuleButtonStyle(prominent: true, tint: Theme.active))
        .popover(isPresented: $isShowingDetails, arrowEdge: .bottom) {
            UpdateDetails()
                .padding(16)
                .frame(width: 300)
                .background(Color(red: 0.09, green: 0.10, blue: 0.13))
                .preferredColorScheme(.dark)
        }
    }
}

/// Version, release notes and the install button; shared with Settings.
struct UpdateDetails: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let updates = app.updates
        VStack(alignment: .leading, spacing: 10) {
            if let manifest = updates.available {
                Text("Polka \(manifest.version) (\(manifest.build))").font(.headline)
                Text("You have \(updates.versionDescription).").font(.caption).foregroundStyle(.secondary)
                if !manifest.notes.isEmpty {
                    ScrollView {
                        Text(manifest.notes)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 140)
                }
                if case .downloading = updates.state {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Downloading and checking the signature…").font(.caption)
                    }
                } else {
                    Button("Install and Restart") { Task { await updates.install() } }
                        .keyboardShortcut(.defaultAction)
                }
            }
            if case .failed(let message) = updates.state {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
