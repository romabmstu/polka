import AppKit
import Observation
import PolkaSystem

@MainActor
@Observable
final class AgendaModel {
    private(set) var access: CalendarService.Access
    private(set) var items: [AgendaItem] = []
    private(set) var next: AgendaItem?
    private(set) var now = Date.now

    @ObservationIgnored private let service = CalendarService()
    @ObservationIgnored private var changeToken: NSObjectProtocol?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init() {
        access = service.access
    }

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
        access = service.access
        reload()
    }

    func reload() {
        access = service.access
        now = .now
        items = service.agenda(on: now)
        next = service.nextEvent(after: now)
    }

    private func tick() {
        let day = Calendar.current.startOfDay(for: now)
        now = .now
        if Calendar.current.startOfDay(for: now) != day || next.map({ $0.end <= now }) == true {
            reload()
        }
    }

    func join(_ item: AgendaItem) {
        guard let meeting = item.meeting else { return }
        NSWorkspace.shared.open(meeting.url)
    }

    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
