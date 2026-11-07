import AppKit
import Observation
import PolkaSystem

@MainActor
@Observable
final class AgendaModel {
    private(set) var access: CalendarService.Access
    /// The day shown in the Calendar section.
    private(set) var day = Calendar.current.startOfDay(for: .now)
    private(set) var items: [AgendaItem] = []
    private(set) var next: AgendaItem?
    private(set) var calendars: [CalendarInfo] = []
    private(set) var now = Date.now

    @ObservationIgnored private let service = CalendarService()
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private var changeToken: NSObjectProtocol?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init(preferences: Preferences) {
        self.preferences = preferences
        access = service.access
    }

    var isShowingToday: Bool { Calendar.current.isDate(day, inSameDayAs: now) }

    func start() {
        guard ticker == nil else { return }
        reload()
        changeToken = service.observeChanges { [weak self] in self?.reload() }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.tick()
            }
        }
    }

    func requestAccess() async {
        _ = await service.requestAccess()
        reload()
    }

    func reload() {
        access = service.access
        now = .now
        let hidden = preferences.hiddenCalendarIDs
        calendars = service.calendars()
        items = service.agenda(on: day, excluding: hidden)
        next = service.nextEvent(after: now, excluding: hidden)
    }

    // MARK: Days

    func show(dayOffset: Int) {
        guard let moved = Calendar.current.date(byAdding: .day, value: dayOffset, to: day) else { return }
        show(moved)
    }

    func show(_ date: Date) {
        day = Calendar.current.startOfDay(for: date)
        reload()
    }

    func showToday() { show(.now) }

    /// Monday-to-Sunday (locale dependent) week around the shown day.
    var week: [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: day) else { return [day] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private func tick() {
        let today = Calendar.current.startOfDay(for: now)
        now = .now
        let dayChanged = Calendar.current.startOfDay(for: now) != today
        if dayChanged, Calendar.current.isDate(day, inSameDayAs: today) {
            day = Calendar.current.startOfDay(for: now)
        }
        if dayChanged || next.map({ $0.end <= now }) == true {
            reload()
        }
    }

    // MARK: Actions

    func join(_ item: AgendaItem) {
        guard let meeting = item.meeting else { return }
        NSWorkspace.shared.open(meeting.url)
    }

    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
