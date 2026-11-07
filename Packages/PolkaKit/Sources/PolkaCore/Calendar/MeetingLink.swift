import Foundation

/// Finds the video-call link in a calendar event so it can be joined in one click.
public enum MeetingLink {
    public enum Service: String, Sendable, CaseIterable {
        case googleMeet, zoom, teams, telemost, jitsi, webex
    }

    public struct Match: Hashable, Sendable {
        public let url: URL
        public let service: Service
    }

    private static let hosts: [(suffix: String, service: Service)] = [
        ("meet.google.com", .googleMeet),
        ("zoom.us", .zoom),
        ("teams.microsoft.com", .teams),
        ("teams.live.com", .teams),
        ("telemost.yandex.ru", .telemost),
        ("telemost.360.yandex.ru", .telemost),
        ("meet.jit.si", .jitsi),
        ("webex.com", .webex),
    ]

    /// Checks the event's URL field first, then location and notes.
    public static func find(url: URL?, location: String?, notes: String?) -> Match? {
        if let url, let match = classify(url) { return match }
        for text in [location, notes].compactMap({ $0 }) {
            for page in LinkExtractor.pages(in: text) {
                if let match = classify(page.url) { return match }
            }
        }
        return nil
    }

    static func classify(_ url: URL) -> Match? {
        guard url.scheme?.lowercased() == "https", let host = url.host(percentEncoded: false)?.lowercased() else {
            return nil
        }
        for (suffix, service) in hosts where host == suffix || host.hasSuffix("." + suffix) {
            return Match(url: url, service: service)
        }
        return nil
    }
}
