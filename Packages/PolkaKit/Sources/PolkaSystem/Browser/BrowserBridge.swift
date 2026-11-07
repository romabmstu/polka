import AppKit
import Foundation
import PolkaCore

/// A browser Polka can read tabs from through AppleScript.
public enum Browser: String, CaseIterable, Sendable, Identifiable {
    case safari, chrome, arc, brave, edge, yandex

    public var id: String { rawValue }

    public var bundleIdentifier: String {
        switch self {
        case .safari: "com.apple.Safari"
        case .chrome: "com.google.Chrome"
        case .arc: "company.thebrowser.Browser"
        case .brave: "com.brave.Browser"
        case .edge: "com.microsoft.edgemac"
        case .yandex: "ru.yandex.desktop.yandex-browser"
        }
    }

    public var name: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Google Chrome"
        case .arc: "Arc"
        case .brave: "Brave"
        case .edge: "Microsoft Edge"
        case .yandex: "Yandex Browser"
        }
    }

    public init?(bundleIdentifier: String) {
        guard let match = Self.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier }) else { return nil }
        self = match
    }

    public var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// Chromium browsers share one scripting dictionary; Safari has its own.
    fileprivate var usesChromiumDictionary: Bool { self != .safari }

    fileprivate var supportsNewWindowScript: Bool { self != .arc }
}

public struct BrowserTab: Hashable, Sendable {
    public let browser: Browser
    public let window: Int
    public let isCurrent: Bool
    public let page: PageReference
}

/// Reads and opens browser tabs through AppleScript.
///
/// Script sources are built only from the fixed `Browser` table, never from
/// input; URLs travel as `argv`. macOS asks once per browser for permission.
public struct BrowserBridge: Sendable {
    public enum Failure: Error, Equatable {
        case notAuthorized(Browser)
        case scriptFailed(String)
    }

    private static let osascript = "/usr/bin/osascript"
    private static let fieldSeparator: Character = "\u{1F}"
    private static let recordSeparator: Character = "\u{1E}"

    private let runner: CommandRunner

    public init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    /// The browser to read from: the frontmost one if it is a browser,
    /// otherwise the most recently used running one.
    @MainActor
    public static func preferredBrowser(recent: [String]) -> Browser? {
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            let browser = Browser(bundleIdentifier: front)
        {
            return browser
        }
        for id in recent {
            if let browser = Browser(bundleIdentifier: id), browser.isRunning { return browser }
        }
        return Browser.allCases.first(where: \.isRunning)
    }

    public func tabs(in browser: Browser) async throws -> [BrowserTab] {
        guard browser.isRunning else { return [] }
        let output = try await runScript(Self.listTabsScript(for: browser), arguments: [], browser: browser)
        return output.split(separator: Self.recordSeparator).compactMap { record in
            let fields = record.split(separator: Self.fieldSeparator, omittingEmptySubsequences: false)
            guard fields.count == 4, let window = Int(fields[0]), let url = URL(string: String(fields[2])),
                URLNormalizer.isSavable(url)
            else { return nil }
            return BrowserTab(
                browser: browser, window: window, isCurrent: fields[1] == "true",
                page: PageReference(url: url, title: String(fields[3])))
        }
    }

    /// The tab the user is looking at in the browser's front window.
    public func currentTab(in browser: Browser) async throws -> PageReference? {
        try await tabs(in: browser).first { $0.window == 1 && $0.isCurrent }?.page
    }

    /// Opens pages in `browser`, in a new window if asked and supported.
    @MainActor
    public func open(_ urls: [URL], in browser: Browser, inNewWindow: Bool) async throws {
        let safe = urls.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
        guard !safe.isEmpty else { return }
        if inNewWindow, browser.supportsNewWindowScript {
            _ = try await runScript(
                Self.newWindowScript(for: browser), arguments: safe.map(\.absoluteString), browser: browser)
            return
        }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier) else {
            safe.forEach { NSWorkspace.shared.open($0) }
            return
        }
        _ = try await NSWorkspace.shared.open(safe, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    private func runScript(_ script: String, arguments: [String], browser: Browser) async throws -> String {
        let result = try await runner.run(Self.osascript, ["-"] + arguments, input: script, timeout: .seconds(10))
        guard result.succeeded else {
            // -1743: the user has not allowed Polka to control this browser.
            if result.errorOutput.contains("-1743") { throw Failure.notAuthorized(browser) }
            throw Failure.scriptFailed(result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.output.trimmingCharacters(in: .newlines)
    }

    // MARK: Scripts

    private static func listTabsScript(for browser: Browser) -> String {
        let current = browser.usesChromiumDictionary ? "id of active tab of w" : "index of current tab of w"
        let key = browser.usesChromiumDictionary ? "id of t" : "index of t"
        let title = browser.usesChromiumDictionary ? "title of t" : "name of t"
        return """
            on run
                set fs to character id 31
                set rs to character id 30
                set out to ""
                tell application id "\(browser.bundleIdentifier)"
                    set wi to 0
                    repeat with w in windows
                        try
                            set currentKey to \(current)
                            set wi to wi + 1
                            repeat with t in tabs of w
                                set u to URL of t
                                if u is missing value then set u to ""
                                set n to \(title)
                                if n is missing value then set n to ""
                                set out to out & wi & fs & ((\(key)) = currentKey) & fs & u & fs & n & rs
                            end repeat
                        end try
                    end repeat
                end tell
                return out
            end run
            """
    }

    private static func newWindowScript(for browser: Browser) -> String {
        if browser == .safari {
            return """
                on run argv
                    tell application id "com.apple.Safari"
                        make new document with properties {URL:(item 1 of argv)}
                        tell front window
                            repeat with i from 2 to (count of argv)
                                make new tab at end of tabs with properties {URL:(item i of argv)}
                            end repeat
                        end tell
                        activate
                    end tell
                end run
                """
        }
        return """
            on run argv
                tell application id "\(browser.bundleIdentifier)"
                    set w to make new window
                    set URL of active tab of w to (item 1 of argv)
                    repeat with i from 2 to (count of argv)
                        make new tab at end of tabs of w with properties {URL:(item i of argv)}
                    end repeat
                    activate
                end tell
            end run
            """
    }
}
