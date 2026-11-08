import Foundation

/// The useful part of a macOS crash report (`.ips`), short enough to paste
/// into an issue.
public struct CrashSummary: Equatable, Sendable {
    public var appName: String
    public var appVersion: String?
    public var timestamp: String?
    public var osVersion: String?
    /// "EXC_BAD_ACCESS (SIGSEGV)".
    public var exception: String
    /// A fatal error message or termination reason, when there is one.
    public var reason: String?
    /// Top of the crashed thread: "Polka  TabsModel.flush() + 120".
    public var frames: [String]

    public var text: String {
        var lines = ["Exception: \(exception)"]
        if let reason { lines.append("Reason: \(reason)") }
        if let appVersion { lines.append("Version: \(appVersion)") }
        if let osVersion { lines.append("OS: \(osVersion)") }
        if let timestamp { lines.append("Time: \(timestamp)") }
        if !frames.isEmpty {
            lines.append("Crashed thread:")
            lines += frames.enumerated().map { "\($0.offset)  \($0.element)" }
        }
        return lines.joined(separator: "\n")
    }
}

/// Reads the JSON crash reports macOS writes to
/// `~/Library/Logs/DiagnosticReports`: a one-line header object, then the
/// report object.
public enum CrashReportParser {
    public static func summary(fromIPS contents: String, frameLimit: Int = 10) -> CrashSummary? {
        guard let newline = contents.firstIndex(of: "\n") else { return nil }
        guard
            let header = object(String(contents[..<newline])),
            let body = object(String(contents[contents.index(after: newline)...]))
        else { return nil }
        // 309 is a crash; hangs and other diagnostics use other types.
        if let type = header["bug_type"] as? String, type != "309" { return nil }

        let name = (header["app_name"] as? String) ?? (header["name"] as? String) ?? (body["procName"] as? String) ?? "?"
        var version = header["app_version"] as? String
        if let build = header["build_version"] as? String, let shown = version {
            version = "\(shown) (\(build))"
        }

        let exceptionInfo = body["exception"] as? [String: Any]
        var exception = (exceptionInfo?["type"] as? String) ?? "unknown"
        if let signal = exceptionInfo?["signal"] as? String { exception += " (\(signal))" }

        var reason: String?
        if let asi = body["asi"] as? [String: Any] {
            reason = asi.values.compactMap { ($0 as? [String])?.first }.first
        }
        if reason == nil, let termination = body["termination"] as? [String: Any] {
            reason = termination["indicator"] as? String
        }

        return CrashSummary(
            appName: name,
            appVersion: version,
            timestamp: header["timestamp"] as? String,
            osVersion: header["os_version"] as? String,
            exception: exception,
            reason: reason.map { String($0.prefix(300)) },
            frames: crashedFrames(body, limit: frameLimit)
        )
    }

    private static func crashedFrames(_ body: [String: Any], limit: Int) -> [String] {
        guard let threads = body["threads"] as? [[String: Any]], !threads.isEmpty else { return [] }
        let index = (body["faultingThread"] as? Int).flatMap { threads.indices.contains($0) ? $0 : nil }
            ?? threads.firstIndex { ($0["triggered"] as? Bool) == true } ?? 0
        let images = (body["usedImages"] as? [[String: Any]]) ?? []
        let frames = (threads[index]["frames"] as? [[String: Any]]) ?? []
        return frames.prefix(limit).map { frame in
            let imageIndex = frame["imageIndex"] as? Int
            let image = imageIndex.flatMap { images.indices.contains($0) ? images[$0]["name"] as? String : nil } ?? "?"
            if let symbol = frame["symbol"] as? String {
                let offset = (frame["symbolLocation"] as? Int).map { " + \($0)" } ?? ""
                return "\(image)  \(symbol)\(offset)"
            }
            let offset = (frame["imageOffset"] as? Int).map { "0x" + String($0, radix: 16) } ?? "?"
            return "\(image)  \(offset)"
        }
    }

    private static func object(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
