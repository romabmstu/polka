import Foundation
import PolkaCore

/// Finds crash reports macOS wrote for Polka since the last look, so the next
/// launch can offer to report them. Reads only Polka's own reports.
enum CrashMonitor {
    struct Report {
        let url: URL
        let date: Date
        let summary: CrashSummary
    }

    private static let lastCheckKey = "lastCrashReportCheck"
    private static let maximumSize = 5_000_000

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/DiagnosticReports", directoryHint: .isDirectory)
    }

    /// The newest unseen crash, if any. The first time this runs it only
    /// records the moment, so crashes from before are never brought up.
    static func newestUnseenReport(defaults: UserDefaults = .standard) -> Report? {
        guard let lastCheck = defaults.object(forKey: lastCheckKey) as? Date else {
            markChecked(upTo: .now, defaults: defaults)
            return nil
        }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        let candidates = files.compactMap { url -> (URL, Date, Int)? in
            let name = url.lastPathComponent
            guard name.hasPrefix("Polka"), url.pathExtension == "ips",
                let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                let date = values.contentModificationDate, date > lastCheck
            else { return nil }
            return (url, date, values.fileSize ?? 0)
        }
        .sorted { $0.1 > $1.1 }

        for (url, date, size) in candidates where size <= maximumSize {
            guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8),
                let summary = CrashReportParser.summary(fromIPS: text), summary.appName == "Polka"
            else { continue }
            return Report(url: url, date: date, summary: summary)
        }
        if let newest = candidates.first { markChecked(upTo: newest.1, defaults: defaults) }
        return nil
    }

    static func markChecked(upTo date: Date, defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: lastCheckKey)
    }
}
