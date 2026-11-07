import PolkaCore
import SwiftUI

struct PanelRootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let panel = app.panel
        VStack(spacing: 0) {
            surface
                .padding(.top, NotchWindowController.topOffset(for: panel.style))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)).animation(.easeOut(duration: 0.22).delay(0.06)))
            } else {
                CollapsedPanel()
                    .transition(.opacity.animation(.easeOut(duration: 0.12)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(panel.hasNotch ? Color.black : Color.black.opacity(0.9))
        .clipShape(shape)
        .overlay {
            if !panel.hasNotch { shape.stroke(Color.white.opacity(0.12), lineWidth: 1) }
        }
        .shadow(color: .black.opacity(panel.isExpanded ? 0.5 : (panel.hasNotch ? 0 : 0.3)), radius: panel.isExpanded ? 26 : 10, y: 10)
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
            RoundedRectangle(cornerRadius: panel.isExpanded ? 26 : PanelState.pillSize.height / 2, style: .continuous))
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
            let wings = CollapsedPanel.hasActivity(app) ? 2 * PanelMetrics.wingWidth : 0
            return CGSize(width: width + shoulders + wings, height: height)
        case .pill:
            return PanelState.pillSize
        }
    }
}
