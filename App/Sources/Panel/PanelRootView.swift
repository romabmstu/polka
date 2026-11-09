import PolkaCore
import SwiftUI
import UniformTypeIdentifiers

struct PanelRootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let panel = app.panel
        VStack(spacing: 0) {
            surface
                .padding(.top, NotchWindowController.topOffset(for: panel.style, expanded: panel.isExpanded))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            guard panel.isExpanded else { return false }
            let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
            for provider in fileProviders {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                    else if let value = item as? URL { url = value }
                    else { url = nil }
                    guard let url, url.isFileURL else { return }
                    Task { @MainActor in
                        app.shelf.add([url])
                        panel.section = .shelf
                    }
                }
            }
            return !fileProviders.isEmpty
        }
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: panel.isExpanded)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: collapsedSize)
    }

    private var surface: some View {
        let panel = app.panel
        let size = panel.isExpanded ? PanelState.expandedSize : collapsedSize
        let shape = surfaceShape

        return ZStack(alignment: .top) {
            if panel.isExpanded {
                ExpandedPanel()
                    .transition(.opacity)
            } else {
                CollapsedPanel()
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background {
            if panel.isExpanded { Theme.panelBackground }
            else { Color.black.opacity(panel.hasNotch ? 1 : 0.88) }
        }
        .clipShape(shape)
        .overlay {
            if !panel.hasNotch { shape.stroke(Color.white.opacity(panel.isExpanded ? 0.12 : 0.16), lineWidth: 0.75) }
        }
        .shadow(color: .black.opacity(panel.isExpanded ? 0.5 : 0), radius: panel.isExpanded ? 26 : 0, y: 10)
        .contentShape(shape)
    }

    private var surfaceShape: AnyShape {
        let panel = app.panel
        if panel.hasNotch {
            return AnyShape(
                NotchShape(
                    shoulderRadius: panel.isExpanded ? 14 : 6,
                    bottomRadius: panel.isExpanded ? PanelMetrics.expandedCorner : 11))
        }
        return AnyShape(
            RoundedRectangle(cornerRadius: panel.isExpanded ? 26 : collapsedSize.height / 2, style: .continuous))
    }

    /// The closed notch is exactly the camera housing when nothing is going on,
    /// and grows "wings" to either side while there is something to show.
    private var collapsedSize: CGSize {
        let panel = app.panel
        switch panel.style {
        case .notch(let width, let height):
            let shoulders: CGFloat = 12
            if panel.flash != nil {
                return CGSize(width: width + shoulders + 2 * PanelMetrics.wingWidth + 60, height: height + 30)
            }
            let wings = CollapsedPanel.hasActivity(app) ? 2 * CollapsedPanel.wingWidth(app) : 0
            return CGSize(width: width + shoulders + wings, height: height)
        case .pill(let menuBar):
            // Only as wide as what it shows: a small handle when idle.
            let height = PanelState.pillHeight(menuBar: menuBar)
            if panel.flash != nil { return CGSize(width: 230, height: height) }
            return CGSize(width: CollapsedPanel.pillWidth(app), height: height)
        }
    }
}
