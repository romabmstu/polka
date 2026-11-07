import AppKit
import Foundation
import PolkaCore

public struct BrowserTab: Hashable, Sendable {
    public let window: Int
    public let isCurrent: Bool
    public let page: PageReference
}

/// Reads and opens Safari tabs through AppleScript.
///
/// Scripts are fixed strings run by `osascript`; URLs travel as `argv`, never
/// spliced into script text, so a page address cannot change what runs.
/// macOS asks the user once for permission to control Safari.
public struct SafariBridge: Sendable {
    public enum Failure: Error, Equatable {
        case notAuthorized
        case scriptFailed(String)
    }

    public static let bundleIdentifier = "com.apple.Safari"
    private static let osascript = "/usr/bin/osascript"
    private static let fieldSeparator: Character = "\u{1F}"
    private static let recordSeparator: Character = "\u{1E}"

    private let runner: CommandRunner

    public init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    /// `false` when Safari is not running; asking it anything would launch it.
    public var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
    }

    public func tabs() async throws -> [BrowserTab] {
        guard isRunning else { return [] }
        let output = try await runScript(Self.listTabsScript, arguments: [])
        return output.split(separator: Self.recordSeparator).compactMap { record in
            let fields = record.split(separator: Self.fieldSeparator, omittingEmptySubsequences: false)
            guard fields.count == 4, let window = Int(fields[0]), let url = URL(string: String(fields[2])),
                URLNormalizer.isSavable(url)
            else { return nil }
            return BrowserTab(
                window: window,
                isCurrent: fields[1] == "true",
                page: PageReference(url: url, title: String(fields[3]))
            )
        }
    }

    /// The tab the user is looking at in the frontmost Safari window.
    public func currentTab() async throws -> PageReference? {
        try await tabs().first { $0.window == 1 && $0.isCurrent }?.page
    }

    /// Opens pages in Safari, optionally in a new window.
    @MainActor
    public func open(_ urls: [URL], inNewWindow: Bool) async throws {
        let safe = urls.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
        guard !safe.isEmpty else { return }
        if inNewWindow {
            _ = try await runScript(Self.openInNewWindowScript, arguments: safe.map(\.absoluteString))
        } else {
            let configuration = NSWorkspace.OpenConfiguration()
            guard let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) else {
                for url in safe { NSWorkspace.shared.open(url) }
                return
            }
            _ = try await NSWorkspace.shared.open(safe, withApplicationAt: safari, configuration: configuration)
        }
    }

    private func runScript(_ script: String, arguments: [String]) async throws -> String {
        let result = try await runner.run(Self.osascript, ["-"] + arguments, input: script, timeout: .seconds(10))
        guard result.succeeded else {
            // -1743: the user has not allowed Polka to control Safari.
            if result.errorOutput.contains("-1743") { throw Failure.notAuthorized }
            throw Failure.scriptFailed(result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.output.trimmingCharacters(in: .newlines)
    }

    private static let listTabsScript = """
        on run
            set fs to character id 31
            set rs to character id 30
            set out to ""
            tell application id "com.apple.Safari"
                set wi to 0
                repeat with w in windows
                    try
                        set currentIndex to index of current tab of w
                        set wi to wi + 1
                        set ti to 0
                        repeat with t in tabs of w
                            set ti to ti + 1
                            set u to URL of t
                            if u is missing value then set u to ""
                            set n to name of t
                            if n is missing value then set n to ""
                            set out to out & wi & fs & (ti = currentIndex) & fs & u & fs & n & rs
                        end repeat
                    end try
                end repeat
            end tell
            return out
        end run
        """

    private static let openInNewWindowScript = """
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
