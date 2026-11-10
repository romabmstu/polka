import SwiftUI
import UniformTypeIdentifiers

struct ShelfSection: View {
    @Environment(AppModel.self) private var app
    @State private var isTargeted = false

    private let columns = [GridItem(.adaptive(minimum: 116), spacing: 10)]

    var body: some View {
        let shelf = app.shelf
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shelf").font(.system(size: 15, weight: .semibold))
                    Text("Drop files here, drag them out later. Files stay where they are.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                if !shelf.items.isEmpty {
                    Button("Clear") { shelf.clear() }.buttonStyle(CapsuleButtonStyle())
                    Button {
                        shelf.airDrop([])
                    } label: {
                        Label("AirDrop", systemImage: "airplayaudio")
                    }
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
                }
            }

            Group {
                if shelf.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 28))
                            .symbolEffect(.bounce, value: isTargeted)
                        Text("Drop files here").font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(shelf.items) { item in
                                ShelfTile(item: item)
                            }
                        }
                        .padding(10)
                    }
                    .scrollIndicators(.never)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isTargeted ? Theme.accent.opacity(0.14) : Color.clear, in: .rect(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Theme.accent : Theme.hairline,
                        style: StrokeStyle(lineWidth: 1.5, dash: shelf.items.isEmpty ? [6, 5] : []))
            }
            .dropDestination(for: URL.self) { urls, _ in
                shelf.add(urls)
                return urls.contains(where: \.isFileURL)
            } isTargeted: { isTargeted = $0 }
        }
        .onAppear { shelf.refresh() }
    }
}

private struct ShelfTile: View {
    @Environment(AppModel.self) private var app
    let item: ShelfModel.Item

    var body: some View {
        let shelf = app.shelf
        VStack(spacing: 6) {
            Image(nsImage: shelf.icon(for: item))
                .resizable()
                .frame(width: 48, height: 48)
                .opacity(item.isMissing ? 0.4 : 1)
            Text(item.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(item.isMissing ? Theme.secondary : Color.primary)
            if item.isMissing {
                Text("File not found").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            } else if let size = shelf.size(of: item) {
                Text(size).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: .rect(cornerRadius: 14, style: .continuous))
        .hoverHighlight(cornerRadius: 14)
        .onDrag { shelf.dragProvider(for: item) }
        .onTapGesture(count: 2) { shelf.open(item) }
        .contextMenu {
            Group {
                Button("Open") { shelf.open(item) }
                Button("Show in Finder") { shelf.reveal(item) }
                Button("AirDrop") { shelf.airDrop([item]) }
            }
            .disabled(item.isMissing)
            Divider()
            Button("Remove from Shelf") { shelf.remove(item) }
        }
        .help(Text(item.url.path(percentEncoded: false)))
    }
}
