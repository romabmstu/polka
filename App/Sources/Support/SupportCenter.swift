import AppKit
import PolkaCore
import PolkaSystem
import SwiftUI

/// First-run welcome, bug reports with diagnostics, and offering to report a
/// crash on the next launch. Nothing is sent anywhere by Polka itself: reports
/// open in the browser, where the user reads them before posting.
@MainActor
final class SupportCenter {
    static let shared = SupportCenter()

    let permissions = PermissionsModel()
    private weak var model: AppModel?
    private var welcomeWindow: NSWindow?
    private var welcomeDelegate: WindowCloseObserver?

    private init() {}

    func start(model: AppModel) {
        self.model = model
        permissions.refresh()
        if !model.preferences.hasSeenWelcome {
            // A fresh install: older crash reports are not ours to bring up.
            CrashMonitor.markChecked(upTo: .now)
            showWelcome()
        } else {
            Task {
                // Let the panel settle before asking anything.
                try? await Task.sleep(for: .seconds(3))
                offerCrashReport()
            }
        }
    }

    // MARK: Welcome

    func showWelcome() {
        guard let model else { return }
        model.panel.collapse()
        if welcomeWindow == nil {
            let view = WelcomeView(permissions: permissions) { [weak self] openPanel in
                self?.welcomeWindow?.close()
                if openPanel {
                    model.panel.section = .overview
                    model.panel.openForKeyboard()
                }
            }
            .environment(model)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = String(localized: "Welcome to Polka", table: "Support")
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()
            let observer = WindowCloseObserver { [weak self] in
                guard let self else { return }
                self.model?.preferences.hasSeenWelcome = true
                // Let go of the window once it is closed, which also stops the
                // view's status polling; not from inside the delegate call.
                Task { @MainActor in
                    self.welcomeWindow = nil
                    self.welcomeDelegate = nil
                }
            }
            window.delegate = observer
            welcomeDelegate = observer
            welcomeWindow = window
        }
        NSApp.activate()
        welcomeWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Reports

    func diagnostics() -> Diagnostics {
        permissions.refresh()
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        let system = "\(SystemInfo.osVersion), \(SystemInfo.modelIdentifier), \(SystemInfo.architecture)"
        var items: [Diagnostics.Item] = []
        if let preferences = model?.preferences {
            items.append(.init("Update channel", preferences.updateChannel.rawValue))
            items.append(.init("Sections", preferences.sections.map(\.rawValue).joined(separator: ", ")))
            items.append(.init("Clipboard history", preferences.clipboardHistoryEnabled ? "on" : "off"))
        }
        let notch = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
        items.append(.init("Displays", "\(NSScreen.screens.count), notch: \(notch ? "yes" : "no")"))
        items.append(.init("Language", Locale.preferredLanguages.first ?? "?"))
        for line in permissions.summary.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                items.append(.init(String(parts[0]), parts[1].trimmingCharacters(in: .whitespaces)))
            }
        }
        return Diagnostics(appVersion: version, system: system, items: items)
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics().text, forType: .string)
        model?.panel.flash(.init(symbol: "doc.on.doc", text: String(localized: "Diagnostics copied", table: "Support")))
    }

    /// Opens a pre-filled bug report on GitHub in the browser.
    func reportProblem(title: String = "", what: String? = nil, details: String? = nil) {
        let url = IssueLink.bugReport(
            title: title,
            what: what ?? "What I did:\n\nWhat I expected:\n\nWhat happened instead:\n",
            diagnostics: diagnostics(),
            details: details)
        NSWorkspace.shared.open(url)
    }

    private func offerCrashReport() {
        guard let report = CrashMonitor.newestUnseenReport() else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Polka quit unexpectedly last time", table: "Support")
        alert.informativeText = String(
            localized: "A report helps fix it. It opens on GitHub with the crash summary and basic system details, and you can read it before posting. Polka also shows the full crash file so you can attach it.",
            table: "Support")
        alert.addButton(withTitle: String(localized: "Report on GitHub…", table: "Support"))
        alert.addButton(withTitle: String(localized: "Not Now", table: "Support"))
        NSApp.activate()
        let response = alert.runModal()
        CrashMonitor.markChecked(upTo: report.date)
        guard response == .alertFirstButtonReturn else { return }
        reportProblem(
            title: "Crash: \(report.summary.exception)",
            what: "Polka quit unexpectedly. The crash file is attached.\n\nWhat I was doing:\n",
            details: report.summary.text)
        NSWorkspace.shared.activateFileViewerSelecting([report.url])
    }
}

/// Calls back when a window closes, however it was closed.
@MainActor
private final class WindowCloseObserver: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
