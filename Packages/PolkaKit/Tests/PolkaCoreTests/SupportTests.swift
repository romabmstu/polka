import Foundation
import Testing

@testable import PolkaCore

@Suite struct IssueLinkTests {
    private let diagnostics = Diagnostics(
        appVersion: "0.1.0 (46)", system: "macOS 26.1 (25B78), Mac15,3, Apple silicon",
        items: [.init("Update channel", "beta"), .init("Calendars", "allowed")])

    private func fields(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    @Test func fillsTheBugReportForm() {
        let url = IssueLink.bugReport(title: "Crash: C++ & more", what: "Steps", diagnostics: diagnostics)
        #expect(url.absoluteString.hasPrefix("https://github.com/romabmstu/polka/issues/new?template=bug_report.yml&"))
        let values = fields(url)
        #expect(values["title"] == "Crash: C++ & more")
        #expect(values["version"] == "0.1.0 (46)")
        #expect(values["macos"] == "macOS 26.1 (25B78), Mac15,3, Apple silicon")
        #expect(values["diagnostics"]?.contains("Update channel: beta") == true)
        #expect(values["logs"] == nil)
        // A literal "+" would be read back as a space.
        #expect(!url.absoluteString.contains("C++"))
    }

    @Test func staysWithinTheLengthLimit() {
        let long = String(repeating: "Ж frame + 0x1234\n", count: 2_000)
        let url = IssueLink.bugReport(title: "Crash", what: "x", diagnostics: diagnostics, details: long)
        #expect(url.absoluteString.count <= IssueLink.maximumLength)
        let values = fields(url)
        #expect(values["logs"]?.hasPrefix("Ж frame + 0x1234") == true)
        #expect(values["logs"]?.hasSuffix("…") == true)
        #expect(values["version"] == "0.1.0 (46)")
    }
}

@Suite struct CrashReportTests {
    private let report = """
        {"app_name":"Polka","timestamp":"2026-11-08 12:00:00.00 +0300","app_version":"0.1.0","build_version":"46","bug_type":"309","os_version":"macOS 26.1 (25B78)","name":"Polka"}
        {
          "procName" : "Polka",
          "exception" : {"type":"EXC_BREAKPOINT","signal":"SIGTRAP","codes":"0x1"},
          "termination" : {"indicator":"Trace/BPT trap: 5"},
          "asi" : {"libswiftCore.dylib":["Polka/TabsModel.swift:120: Fatal error: Index out of range"]},
          "faultingThread" : 1,
          "threads" : [
            {"frames":[{"imageIndex":1,"imageOffset":10}]},
            {"triggered":true,"frames":[
              {"imageIndex":1,"symbol":"_assertionFailure(_:_:file:line:flags:)","symbolLocation":180},
              {"imageIndex":0,"symbol":"TabsModel.flush()","symbolLocation":120},
              {"imageIndex":0,"imageOffset":4096},
              {"imageIndex":7,"imageOffset":16}
            ]}
          ],
          "usedImages" : [{"name":"Polka"},{"name":"libswiftCore.dylib"}]
        }
        """

    @Test func summarizesTheCrashedThread() throws {
        let summary = try #require(CrashReportParser.summary(fromIPS: report))
        #expect(summary.appName == "Polka")
        #expect(summary.appVersion == "0.1.0 (46)")
        #expect(summary.exception == "EXC_BREAKPOINT (SIGTRAP)")
        #expect(summary.reason == "Polka/TabsModel.swift:120: Fatal error: Index out of range")
        #expect(summary.frames == [
            "libswiftCore.dylib  _assertionFailure(_:_:file:line:flags:) + 180",
            "Polka  TabsModel.flush() + 120",
            "Polka  0x1000",
            "?  0x10",
        ])
        #expect(summary.text.contains("Crashed thread:\n0  libswiftCore.dylib"))
    }

    @Test func ignoresOtherReportsAndJunk() {
        let hang = report.replacingOccurrences(of: "\"bug_type\":\"309\"", with: "\"bug_type\":\"288\"")
        #expect(CrashReportParser.summary(fromIPS: hang) == nil)
        #expect(CrashReportParser.summary(fromIPS: "not json") == nil)
        #expect(CrashReportParser.summary(fromIPS: "{}\n{") == nil)
    }
}
