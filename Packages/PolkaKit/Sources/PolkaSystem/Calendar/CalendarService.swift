import AppKit
import EventKit
import PolkaCore

public struct AgendaItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let location: String?
    public let calendarColorHex: String?
    public let meeting: MeetingLink.Match?

    public func isHappening(at date: Date) -> Bool { start <= date && date < end }
}

/// Today's events from the system calendar database. Google, iCloud and Exchange
/// calendars added in System Settings › Internet Accounts all appear here, so
/// no separate sign-in or network access is needed.
@MainActor
public final class CalendarService {
    public enum Access: Equatable, Sendable {
        case notDetermined, denied, granted
    }

    private let store = EKEventStore()

    public init() {}

    public var access: Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess, .authorized: .granted
        default: .denied
        }
    }

    public func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Calls `handler` whenever events change on any synced calendar.
    /// Keep the returned token for as long as updates are wanted.
    public func observeChanges(_ handler: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    public func agenda(on day: Date, calendar: Calendar = .current) -> [AgendaItem] {
        guard access == .granted else { return [] }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map(AgendaItem.init)
    }

    /// The first timed event that has not ended yet within the next `horizon`.
    public func nextEvent(after date: Date = .now, horizon: TimeInterval = 24 * 60 * 60) -> AgendaItem? {
        guard access == .granted else { return nil }
        let predicate = store.predicateForEvents(withStart: date, end: date.addingTimeInterval(horizon), calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && $0.endDate > date }
            .min { $0.startDate < $1.startDate }
            .map(AgendaItem.init)
    }
}

extension AgendaItem {
    @MainActor
    fileprivate init(_ event: EKEvent) {
        self.init(
            id: event.calendarItemIdentifier + "@" + String(event.startDate.timeIntervalSince1970),
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            calendarColorHex: event.calendar?.color.flatMap(Self.hex),
            meeting: MeetingLink.find(url: event.url, location: event.location, notes: event.notes)
        )
    }

    private static func hex(_ color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
