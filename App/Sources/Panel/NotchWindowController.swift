import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Borderless panel that sits above the menu bar and never steals focus from
/// the app the user is working in.
final class NotchPanel: NSPanel {
    var onCancel: () -> Void = {}

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }
}

/// Positions the panel on the right display and decides when it opens and
/// closes. The window is always as large as the open panel; while collapsed it
/// lets every click through, so the menu bar under it keeps working.
@MainActor
final class NotchWindowController {
    private static let shadowMargin: CGFloat = 40
    private static let closeDelay: Duration = .milliseconds(320)

    private let model: AppModel
    private let panel = NotchPanel()
    private var screen: NSScreen?
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var hoverTask: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        let host = NSHostingView(rootView: PanelRootView().environment(model))
        host.sizingOptions = []
        panel.contentView = host
        panel.onCancel = { [weak self] in self?.model.panel.collapse() }
        model.panel.onExpand = { [weak self] in self?.didExpand() }
        model.panel.onCollapse = { [weak self] in self?.didCollapse() }
        model.panel.openForKeyboard = { [weak self] in self?.openForKeyboard() }
    }

    func show() {
        layout()
        panel.orderFrontRegardless()
        installMonitors()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        observeDisplayPreference()
    }

    func toggleFromKeyboard() {
        if model.panel.isExpanded {
            model.panel.collapse()
        } else {
            openForKeyboard()
        }
    }

    private func openForKeyboard() {
        if !model.panel.isExpanded { layout() }
        model.panel.expand(pinned: true)
        panel.makeKey()
    }

    // MARK: Layout

    private func targetScreen() -> NSScreen? {
        switch model.preferences.display {
        case .pointer:
            Self.screen(at: NSEvent.mouseLocation) ?? screen ?? NSScreen.screens.first
        case .builtIn:
            NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
        case .main:
            NSScreen.screens.first
        }
    }

    private func layout() {
        guard let screen = targetScreen() else { return }
        self.screen = screen
        let style = Self.style(for: screen)
        model.panel.style = style

        let expanded = PanelState.expandedSize
        let width = expanded.width + Self.shadowMargin * 2
        let height = expanded.height + Self.topOffset(for: style, expanded: true) + Self.shadowMargin
        let frame = NSRect(
            x: (screen.frame.midX - width / 2).rounded(),
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
        panel.setFrame(frame, display: true)
    }

    private func observeDisplayPreference() {
        withObservationTracking {
            _ = model.preferences.display
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.layout()
                self?.observeDisplayPreference()
            }
        }
    }

    static func screen(at point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    static func style(for screen: NSScreen) -> PanelState.Style {
        if screen.safeAreaInsets.top > 0,
            let left = screen.auxiliaryTopLeftArea,
            let right = screen.auxiliaryTopRightArea
        {
            return .notch(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        }
        let menuBar = NSStatusBar.system.thickness
        return .pill(menuBarHeight: menuBar)
    }

    /// Distance from the top of the screen to the panel surface. On displays
    /// without a notch the closed capsule is centered in the menu bar and the
    /// open panel drops down just below it.
    static func topOffset(for style: PanelState.Style, expanded: Bool) -> CGFloat {
        switch style {
        case .notch: 0
        case .pill(let menuBar):
            expanded ? menuBar + PanelState.pillPanelGap : PanelState.pillInset
        }
    }

    // MARK: Hit areas (screen coordinates)

    private var collapsedArea: NSRect {
        guard let screen else { return .zero }
        switch model.panel.style {
        case .notch(let width, let height):
            let w = width + 2 * PanelMetrics.wingWidth
            return NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - height - 2, width: w, height: height + 2)
        case .pill(let menuBar):
            return NSRect(
                x: screen.frame.midX - PanelState.pillHitWidth / 2,
                y: screen.frame.maxY - menuBar,
                width: PanelState.pillHitWidth,
                height: menuBar
            )
        }
    }

    private var expandedArea: NSRect {
        guard let screen else { return .zero }
        let size = PanelState.expandedSize
        let top = Self.topOffset(for: model.panel.style, expanded: true)
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - top - size.height,
            width: size.width,
            height: size.height + top
        ).insetBy(dx: -14, dy: -14)
    }

    // MARK: Mouse

    private func installMonitors() {
        let movement: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        let global = NSEvent.addGlobalMonitorForEvents(matching: movement) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved(isDragging: event.type == .leftMouseDragged) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: movement) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved(isDragging: event.type == .leftMouseDragged) }
            return event
        }
        let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedElsewhere() }
        }
        monitors = [global, local, clicks].compactMap { $0 }
    }

    private func pointerMoved(isDragging: Bool) {
        let point = NSEvent.mouseLocation
        let state = model.panel

        if state.isExpanded {
            if expandedArea.contains(point) {
                if isDragging, NSPasteboard(name: .drag).availableType(from: [.fileURL]) != nil {
                    state.section = .shelf
                }
                cancelHover()
            } else if !state.isPinned, !state.isEditingText, hoverTask == nil {
                hoverTask = Task { [weak self] in
                    try? await Task.sleep(for: Self.closeDelay)
                    guard let self, !Task.isCancelled else { return }
                    self.hoverTask = nil
                    if !self.expandedArea.contains(NSEvent.mouseLocation) { self.model.panel.collapse() }
                }
            }
            return
        }

        // Follow the pointer to another display while closed.
        if model.preferences.display == .pointer, let pointerScreen = Self.screen(at: point), pointerScreen != screen {
            cancelHover()
            layout()
        }

        if isDragging, collapsedArea.contains(point),
            NSPasteboard(name: .drag).availableType(from: [.fileURL]) != nil {
            cancelHover()
            state.section = .shelf
            state.expand()
            return
        }

        guard model.preferences.openOnHover else { return }
        if collapsedArea.contains(point) {
            guard hoverTask == nil else { return }
            let delay = Duration.milliseconds(Int(model.preferences.hoverDelay * 1000))
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled else { return }
                self.hoverTask = nil
                if self.collapsedArea.contains(NSEvent.mouseLocation) { self.model.panel.expand() }
            }
        } else {
            cancelHover()
        }
    }

    private func clickedElsewhere() {
        let point = NSEvent.mouseLocation
        let state = model.panel
        if state.isExpanded {
            if !state.isPinned, !expandedArea.contains(point) { state.collapse() }
        } else if collapsedArea.contains(point) {
            state.expand()
        }
    }

    private func cancelHover() {
        hoverTask?.cancel()
        hoverTask = nil
    }

    // MARK: State changes

    private func didExpand() {
        cancelHover()
        panel.ignoresMouseEvents = false
        model.panelDidExpand()
    }

    private func didCollapse() {
        cancelHover()
        panel.ignoresMouseEvents = true
        if panel.isKeyWindow { panel.resignKey() }
        model.panelDidCollapse()
    }
}
