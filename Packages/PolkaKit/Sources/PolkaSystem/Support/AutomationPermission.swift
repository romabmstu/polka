import CoreServices
import Foundation

/// Whether Polka may send Apple Events to another app (Privacy & Security ›
/// Automation), asked without showing a prompt unless requested.
public enum AutomationPermission {
    public enum State: Equatable, Sendable {
        case granted
        case denied
        /// macOS has not asked yet; the first request shows its prompt.
        case notAsked
        /// macOS can only answer while the other app is running.
        case appNotRunning
        case unknown(OSStatus)
    }

    /// Never shows a prompt.
    public static func state(of bundleIdentifier: String) -> State {
        determine(bundleIdentifier, ask: false)
    }

    /// Shows the system prompt if the user has not decided yet. Blocks until
    /// they answer, so call it off the main thread.
    public static func request(_ bundleIdentifier: String) async -> State {
        await Task.detached(priority: .userInitiated) { determine(bundleIdentifier, ask: true) }.value
    }

    private static func determine(_ bundleIdentifier: String, ask: Bool) -> State {
        var target = AEAddressDesc()
        let bytes = Array(bundleIdentifier.utf8)
        let created = bytes.withUnsafeBytes { raw in
            AECreateDesc(DescType(typeApplicationBundleID), raw.baseAddress, raw.count, &target)
        }
        guard created == OSErr(noErr) else { return .unknown(OSStatus(created)) }
        defer { AEDisposeDesc(&target) }

        let status = AEDeterminePermissionToAutomateTarget(
            &target, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
        switch status {
        case OSStatus(noErr): return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        case OSStatus(procNotFound): return .appNotRunning
        default: return .unknown(status)
        }
    }
}

/// Facts about the Mac for bug reports.
public enum SystemInfo {
    /// "Mac15,3".
    public static var modelIdentifier: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// "macOS 26.1 (25B78)".
    public static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let number = "\(version.majorVersion).\(version.minorVersion)" + (version.patchVersion > 0 ? ".\(version.patchVersion)" : "")
        let full = ProcessInfo.processInfo.operatingSystemVersionString
        let build = full.range(of: "Build ").map { String(full[$0.upperBound...].prefix { $0 != ")" }) }
        return "macOS \(number)" + (build.map { " (\($0))" } ?? "")
    }

    public static var architecture: String {
        #if arch(arm64)
            return "Apple silicon"
        #else
            return "Intel"
        #endif
    }
}
