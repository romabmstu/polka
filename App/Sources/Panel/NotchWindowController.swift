import AppKit
import PolkaCore
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

    override func sendEvent(_ event: NSEvent) {
        // Hovering must not steal focus, but an explicit click inside the
        // shelf should make keyboard shortcuts work in the shelf.
        if (event.type == .leftMouseDown || event.type == .rightMouseDown), !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }

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
    private var wakeObservers: [NSObjectProtocol] = []
    private var windowObserver: NSObjectProtocol?
    private var settleTask: Task<Void, Never>?
    /// Display frames as of the last layout, for following the pointer
    /// without asking AppKit about every display on each mouse move.
    private var knownDisplays: [DisplayInfo] = []
    private var hoverTask: Task<Void, Never>?
    private var suppressHoverUntilExit = false

    init(model: AppModel) {
        self.model = model
        let host = NSHostingView(rootView: PanelRootView().environment(model))
        host.sizingOptions = []
        panel.contentView = host
        panel.onCancel = { [weak self] in self?.model.panel.collapse() }
        model.panel.onExpand = { [weak self] in self?.didExpand() }
        model.panel.onCollapse = { [weak self] in self?.didCollapse() }
        model.panel.openForKeyboard = { [weak self] in self?.openForKeyboard() }
        model.panel.focusForTextEditing = { [weak self] in self?.panel.makeKey() }
    }

    func show() {
        layout()
        panel.orderFrontRegardless()
        installMonitors()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysChanged() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        wakeObservers = [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification].map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.displaysChanged() }
            }
        }
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = NSApp.keyWindow, self.isAuxiliaryWindow(window) else { return }
                self.cancelHover()
                self.model.panel.collapse()
            }
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

    /// Connected displays with what Polka needs to know about each one,
    /// main display first.
    static func displays() -> [(screen: NSScreen, info: DisplayInfo)] {
        NSScreen.screens.map { screen in
            let id = screen.displayID
            let info = DisplayInfo(
                id: id,
                frame: screen.frame,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                safeAreaTop: screen.safeAreaInsets.top,
                topLeftArea: screen.auxiliaryTopLeftArea,
                topRightArea: screen.auxiliaryTopRightArea
            )
            return (screen, info)
        }
    }

    private func targetScreen() -> NSScreen? {
        let displays = Self.displays()
        knownDisplays = displays.map { $0.info }
        func screenOf(_ info: DisplayInfo?) -> NSScreen? {
            info.flatMap { info in displays.first { $0.info.id == info.id }?.screen }
        }
        switch model.preferences.display {
        case .pointer:
            let current = displays.first { $0.info.id == self.screen?.displayID }?.screen
            return screenOf(DisplayGeometry.display(at: NSEvent.mouseLocation, in: knownDisplays))
                ?? current ?? displays.first?.screen
        case .builtIn:
            return screenOf(DisplayGeometry.builtIn(in: knownDisplays))
        case .main:
            return displays.first?.screen
        }
    }

    private func layout() {
        guard let screen = targetScreen() else { return }
        self.screen = screen
        let style = Self.style(for: screen)
        if model.panel.style != style { model.panel.style = style }

        let expanded = PanelState.expandedSize
        let width = expanded.width + Self.shadowMargin * 2
        let height = expanded.height + Self.topOffset(for: style, expanded: true) + Self.shadowMargin
        let frame = NSRect(
            x: (screen.frame.midX - width / 2).rounded(),
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    /// A display was attached, removed, rearranged or woke up. macOS sends
    /// this before every display has settled: the notch can read as missing
    /// for a moment, especially on the built-in display right after a monitor
    /// is connected. Lay out now and look again once things have settled.
    private func displaysChanged() {
        layout()
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            for delay in [Duration.milliseconds(400), .milliseconds(1500), .seconds(4)] {
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled else { return }
                // An open panel stays where the user is working with it.
                if !self.model.panel.isExpanded { self.layout() }
            }
        }
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

    static func style(for screen: NSScreen) -> PanelState.Style {
        let info = DisplayInfo(
            id: screen.displayID,
            frame: screen.frame,
            isBuiltIn: false,
            safeAreaTop: screen.safeAreaInsets.top,
            topLeftArea: screen.auxiliaryTopLeftArea,
            topRightArea: screen.auxiliaryTopRightArea
        )
        if let notch = info.notch {
            return .notch(width: notch.width, height: notch.height)
        }
        return .pill(menuBarHeight: NSStatusBar.system.thickness)
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
            let w = width + 2 * CollapsedPanel.wingWidth(model)
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
                cancelHover()
            } else if !state.isPinned, !state.isEditingText, hoverTask == nil {
                hoverTask = Task { [weak self] in
                    try? await Task.sleep(for: Self.closeDelay)
                    guard let self, !Task.isCancelled else { return }
                    self.hoverTask = nil
                    let state = self.model.panel
                    if !state.isPinned, !state.isEditingText, !self.expandedArea.contains(NSEvent.mouseLocation) {
                        state.collapse()
                    }
                }
            }
            return
        }

        // Follow the pointer to another display while closed.
        if model.preferences.display == .pointer,
            let pointer = DisplayGeometry.display(at: point, in: knownDisplays),
            pointer.id != screen?.displayID
        {
            cancelHover()
            layout()
        }

        if suppressHoverUntilExit {
            if collapsedArea.contains(point) { return }
            suppressHoverUntilExit = false
        }

        // A settings or setup window must remain usable above the shelf.
        if NSApp.windows.contains(where: { isAuxiliaryWindow($0) && $0.isVisible && $0.isKeyWindow }) {
            cancelHover()
            return
        }

        if isDragging, collapsedArea.contains(point) {
            cancelHover()
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
            suppressHoverUntilExit = false
            state.expand()
        }
    }

    private func cancelHover() {
        hoverTask?.cancel()
        hoverTask = nil
    }

    /// Popovers and context menus may become key too; they are part of the
    /// shelf and must not collapse it like a separate settings window.
    private func isAuxiliaryWindow(_ window: NSWindow) -> Bool {
        window !== panel && (window.styleMask.contains(.titled) || window is NSSavePanel)
    }

    // MARK: State changes

    private func didExpand() {
        cancelHover()
        panel.ignoresMouseEvents = false
        model.panelDidExpand()
    }

    private func didCollapse() {
        cancelHover()
        suppressHoverUntilExit = collapsedArea.contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = true
        if panel.isKeyWindow { panel.resignKey() }
        model.panelDidCollapse()
    }
}

extension NSScreen {
    /// The Core Graphics display number, stable while the display stays
    /// connected (unlike the `NSScreen` object, which macOS replaces whenever
    /// the arrangement changes).
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
