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
            // Read now, before the first update check, so a rolled-back build
            // is not offered again.
            let rolledBack = UpdateRecovery.takeRolledBackBuild()
            Task {
                // Let the panel settle before asking anything.
                try? await Task.sleep(for: .seconds(3))
                if let rolledBack {
                    explainRollback(from: rolledBack)
                } else {
                    offerCrashReport()
                }
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
        let displays = NotchWindowController.displays().map { $0.info }
        items.append(.init("Displays", displays.enumerated().map { index, display in
            var parts = [display.isBuiltIn ? "built-in" : "external"]
            if index == 0 { parts.append("main") }
            parts.append("\(Int(display.frame.width))×\(Int(display.frame.height))")
            if let notch = display.notch {
                parts.append("notch \(Int(notch.width))×\(Int(notch.height))")
            } else {
                parts.append("no notch (safe area \(Int(display.safeAreaTop)), side areas \(display.topLeftArea == nil ? "none" : "yes"))")
            }
            return parts.joined(separator: " ")
        }.joined(separator: "; ")))
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

extension SupportCenter {
    /// After an update crashed at launch and the previous version was put
    /// back: says what happened and offers to report the crash.
    fileprivate func explainRollback(from build: Int) {
        let report = CrashMonitor.newestUnseenReport()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Polka went back to the previous version", table: "Support")
        alert.informativeText = String(
            localized: "The update to build \(build) closed right after it started, so Polka put back the version you had. That build won’t be installed automatically. A report on GitHub helps fix it.",
            table: "Support")
        alert.addButton(withTitle: String(localized: "Report on GitHub…", table: "Support"))
        alert.addButton(withTitle: String(localized: "Not Now", table: "Support"))
        NSApp.activate()
        let response = alert.runModal()
        if let report { CrashMonitor.markChecked(upTo: report.date) }
        guard response == .alertFirstButtonReturn else { return }
        reportProblem(
            title: report.map { "Update to build \(build) crashed: \($0.summary.exception)" } ?? "Update to build \(build) crashed at launch",
            what: "Polka was rolled back after the update to build \(build) crashed at launch.\n\nWhat I was doing:\n",
            details: report?.summary.text)
        if let report { NSWorkspace.shared.activateFileViewerSelecting([report.url]) }
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
