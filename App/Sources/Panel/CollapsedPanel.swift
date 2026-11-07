import PolkaCore
import PolkaSystem
import SwiftUI

/// What the closed notch shows: live status in the "wings" on either side of
/// the camera, or a short confirmation after an action.
struct CollapsedPanel: View {
    @Environment(AppModel.self) private var app

    /// Meetings starting within this window get a countdown in the notch.
    static let meetingLeadTime: TimeInterval = 30 * 60

    static func hasActivity(_ app: AppModel) -> Bool {
        upcomingMeeting(app) != nil || app.vpn.active != nil
    }

    static func upcomingMeeting(_ app: AppModel) -> AgendaItem? {
        guard let next = app.agenda.next else { return nil }
        let lead = next.start.timeIntervalSince(app.agenda.now)
        return lead <= meetingLeadTime && next.end > app.agenda.now ? next : nil
    }

    var body: some View {
        switch app.panel.style {
        case .notch(_, let height):
            notchContent(notchHeight: height)
        case .pill:
            pillContent
        }
    }

    // MARK: Notch

    @ViewBuilder
    private func notchContent(notchHeight: CGFloat) -> some View {
        if let flash = app.panel.flash {
            VStack(spacing: 0) {
                Color.clear.frame(height: notchHeight)
                Label(flash.text, systemImage: flash.symbol)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 24)
                    .frame(height: 26)
            }
            .foregroundStyle(.white)
        } else {
            HStack(spacing: 0) {
                leadingStatus
                    .frame(width: PanelMetrics.wingWidth, alignment: .leading)
                    .padding(.leading, 14)
                Spacer(minLength: 0)
                trailingStatus
                    .frame(width: PanelMetrics.wingWidth, alignment: .trailing)
                    .padding(.trailing, 14)
            }
            .frame(height: notchHeight)
        }
    }

    // MARK: Pill

    private var pillContent: some View {
        HStack(spacing: 8) {
            if let flash = app.panel.flash {
                Image(systemName: flash.symbol)
                Text(flash.text).lineLimit(1)
            } else {
                Image(systemName: "square.on.square")
                    .foregroundStyle(Theme.secondary)
                leadingStatus
                Spacer(minLength: 0)
                trailingStatus
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
    }

    // MARK: Status pieces

    @ViewBuilder
    private var leadingStatus: some View {
        if let meeting = Self.upcomingMeeting(app) {
            let minutes = max(0, Int(meeting.start.timeIntervalSince(app.agenda.now) / 60))
            HStack(spacing: 5) {
                Image(systemName: meeting.isHappening(at: app.agenda.now) ? "video.fill" : "calendar")
                    .foregroundStyle(Theme.accent)
                Text(meeting.isHappening(at: app.agenda.now) ? String(localized: "now") : String(localized: "\(minutes) min"))
                    .monospacedDigit()
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var trailingStatus: some View {
        if let active = app.vpn.active {
            Image(systemName: active.status == .connected ? "lock.shield.fill" : "lock.shield")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.active)
                .symbolEffect(.pulse, isActive: active.status == .connecting)
                .help(Text(active.name))
        }
    }
}
