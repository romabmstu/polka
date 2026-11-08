import PolkaCore
import SwiftUI

struct ClipboardSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let clipboard = app.clipboard
        if !app.preferences.clipboardHistoryEnabled {
            Placeholder(
                symbol: "doc.on.clipboard",
                title: "Clipboard history is off",
                message: "When on, Polka remembers the last 30 things you copied, pictures included — in memory only, never on disk. Passwords are skipped."
            ) {
                Button("Turn On") {
                    app.preferences.clipboardHistoryEnabled = true
                    clipboard.setEnabled(true)
                }
                .buttonStyle(CapsuleButtonStyle(prominent: true))
            }
        } else if clipboard.history.entries.isEmpty {
            Placeholder(
                symbol: "doc.on.clipboard",
                title: "Nothing copied yet",
                message: "Copy some text or a picture and it shows up here. Kept in memory only; passwords are skipped."
            )
        } else {
            VStack(spacing: 8) {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(clipboard.history.entries) { entry in
                            ClipboardRow(entry: entry, justCopied: clipboard.lastCopiedID == entry.id)
                        }
                    }
                }
                .scrollIndicators(.never)
                HStack {
                    Label("In memory only. Passwords and one-time codes are skipped.", systemImage: "lock")
                        .foregroundStyle(Theme.tertiary)
                    Spacer()
                    Button("Clear") { clipboard.clear() }
                        .buttonStyle(CapsuleButtonStyle())
                }
                .font(.system(size: 11.5))
            }
        }
    }
}

private struct ClipboardRow: View {
    @Environment(AppModel.self) private var app
    let entry: ClipboardHistory.Entry
    let justCopied: Bool

    var body: some View {
        Button {
            app.clipboard.copy(entry)
            app.panel.flash(.init(symbol: "doc.on.doc", text: String(localized: "Copied")))
        } label: {
            HStack(spacing: 12) {
                if entry.kind == .image, let thumbnail = app.clipboard.thumbnail(for: entry) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 32)
                        .clipShape(.rect(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.hairline))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Theme.card, in: .rect(cornerRadius: 8, style: .continuous))
                }
                if let image = entry.image {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Image").font(.system(size: 13))
                        Text(
                            verbatim: "\(image.pixelWidth)×\(image.pixelHeight) · \(Int64(image.png.count).formatted(.byteCount(style: .file)))"
                        )
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                    }
                } else {
                    Text(entry.text.replacingOccurrences(of: "\n", with: " ⏎ "))
                        .font(entry.kind == .code ? .system(size: 12.5, design: .monospaced) : .system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text(entry.copiedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)
                Button {
                    app.clipboard.togglePin(entry)
                } label: {
                    Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                }
                .buttonStyle(IconButtonStyle(size: 24))
                .foregroundStyle(entry.isPinned ? Theme.active : Theme.tertiary)
                .disabled(!app.clipboard.canPin(entry))
                .help(
                    entry.isPinned
                        ? Text("Unpin")
                        : app.clipboard.canPin(entry)
                            ? Text("Pin")
                            : Text("Pinned pictures already use their share of memory. Unpin one first.", tableName: "Support"))
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .contextMenu {
            Button("Copy") { app.clipboard.copy(entry) }
            if entry.image != nil {
                Button("Add to Shelf") {
                    if let image = entry.image, app.shelf.add(png: image.png, copiedAt: entry.copiedAt) {
                        app.panel.flash(.init(symbol: "tray.and.arrow.down", text: String(localized: "Added to Shelf")))
                    }
                }
            }
            Button("Delete", role: .destructive) { app.clipboard.remove(entry) }
        }
    }

    private var icon: String {
        switch entry.kind {
        case .link: "link"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .text: "text.alignleft"
        case .image: "photo"
        }
    }
}
