import PolkaCore
import PolkaSystem
import SwiftUI

struct CalendarSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let agenda = app.agenda
        switch agenda.access {
        case .notDetermined:
            Placeholder(
                symbol: "calendar",
                title: "Your day at a glance",
                message:
                    "Polka reads the calendars already on this Mac — Google, iCloud, Exchange. Nothing leaves your computer."
            ) {
                Button("Allow Calendar") { Task { await agenda.requestAccess() } }
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
            }
        case .denied:
            Placeholder(
                symbol: "calendar.badge.exclamationmark",
                title: "No access to Calendar",
                message: "Turn on Polka in Privacy & Security › Calendars."
            ) {
                Button("Open Settings") { SystemSettings.open(.calendars) }
                    .buttonStyle(CapsuleButtonStyle())
            }
        case .granted:
            HStack(alignment: .top, spacing: 14) {
                timeline
                NextCard()
                    .frame(width: 270)
            }
        }
    }

    private var timeline: some View {
        let agenda = app.agenda
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Today").font(.system(size: 19, weight: .bold))
                Text(agenda.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Button {
                    agenda.openCalendarApp()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(IconButtonStyle(size: 26))
                .help(Text("Open Calendar"))
            }
            if agenda.items.isEmpty {
                Placeholder(symbol: "sun.max", title: "A free day", message: "There are no events today.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(rows) { row in
                                switch row {
                                case .now(let date):
                                    NowLine(date: date).id("now")
                                case .event(let item):
                                    EventRow(item: item, now: agenda.now, isNext: item.id == agenda.next?.id)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .onAppear { proxy.scrollTo("now", anchor: .center) }
                }
            }
        }
    }

    private enum Row: Identifiable {
        case now(Date)
        case event(AgendaItem)

        var id: String {
            switch self {
            case .now: "now"
            case .event(let item): item.id
            }
        }
    }

    private var rows: [Row] {
        let agenda = app.agenda
        var result: [Row] = []
        var placedNow = false
        for item in agenda.items {
            if !placedNow, !item.isAllDay, item.start > agenda.now {
                result.append(.now(agenda.now))
                placedNow = true
            }
            result.append(.event(item))
        }
        if !placedNow { result.append(.now(agenda.now)) }
        return result
    }
}

private struct NowLine: View {
    let date: Date

    var body: some View {
        HStack(spacing: 8) {
            Text(date, format: .dateTime.hour().minute())
                .font(.system(size: 11.5, weight: .bold).monospacedDigit())
                .frame(width: 48, alignment: .leading)
            Circle().frame(width: 7, height: 7)
            Rectangle().frame(height: 1.5)
        }
        .foregroundStyle(Color(red: 1, green: 0.41, blue: 0.38))
        .padding(.horizontal, 8)
        .frame(height: 20)
    }
}

private struct EventRow: View {
    @Environment(AppModel.self) private var app
    let item: AgendaItem
    let now: Date
    let isNext: Bool

    var body: some View {
        let isPast = item.end <= now
        HStack(spacing: 12) {
            Group {
                if item.isAllDay {
                    Text("All day")
                } else {
                    Text(item.start, format: .dateTime.hour().minute())
                }
            }
            .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
            .frame(width: 48, alignment: .leading)

            RoundedRectangle(cornerRadius: 2)
                .fill(item.calendarColorHex.flatMap(Color.init(hex:)) ?? Theme.accent)
                .frame(width: 4, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                if let location = item.location, !location.isEmpty {
                    Text(location).font(.system(size: 11.5)).foregroundStyle(Theme.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if item.meeting != nil, !isPast {
                Button("Join") { app.agenda.join(item) }
                    .buttonStyle(CapsuleButtonStyle(prominent: isNext || item.isHappening(at: now)))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 48)
        .background(isNext ? Theme.accent.opacity(0.14) : .clear, in: .rect(cornerRadius: 12, style: .continuous))
        .opacity(isPast ? 0.45 : 1)
    }
}

private struct NextCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let agenda = app.agenda
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 6) {
                CardLabel("Up next")
                if let next = agenda.next {
                    Text(Countdown.text(to: next.start, now: agenda.now))
                        .font(.system(size: 30, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 4)
                    Text(next.title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                    Text(next.start, format: .dateTime.hour().minute())
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondary)
                    Spacer(minLength: 8)
                    if let meeting = next.meeting {
                        Button {
                            agenda.join(next)
                        } label: {
                            Label("Join \(meeting.service.displayName)", systemImage: "video.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CapsuleButtonStyle(prominent: true))
                    }
                } else {
                    Text("Nothing else today").font(.system(size: 16, weight: .semibold)).padding(.top, 4)
                    Spacer()
                }
            }
        }
    }
}

extension MeetingLinkService {
    var displayName: String {
        switch self {
        case .googleMeet: "Google Meet"
        case .zoom: "Zoom"
        case .teams: "Teams"
        case .telemost: String(localized: "Telemost")
        case .jitsi: "Jitsi"
        case .webex: "Webex"
        }
    }
}

typealias MeetingLinkService = PolkaCore.MeetingLink.Service
