import PolkaCore
import PolkaSystem
import SwiftUI

/// What the closed notch shows: live status in the "wings" on either side of
/// the camera, or a short confirmation after an action.
struct CollapsedPanel: View {
    @Environment(AppModel.self) private var app

    static func hasActivity(_ app: AppModel) -> Bool {
        upcomingMeeting(app) != nil || showsVPN(app) || showsMusic(app)
    }

    static func upcomingMeeting(_ app: AppModel) -> AgendaItem? {
        guard app.preferences.showMeetingCountdown, let next = app.agenda.next else { return nil }
        let lead = next.start.timeIntervalSince(app.agenda.now)
        let window = TimeInterval(app.preferences.meetingLeadMinutes * 60)
        return lead <= window && next.end > app.agenda.now ? next : nil
    }

    static func showsVPN(_ app: AppModel) -> Bool {
        app.preferences.showVPNIndicator && app.vpn.active != nil
    }

    static func showsMusic(_ app: AppModel) -> Bool {
        app.preferences.showMusicIndicator && app.media.isPlaying
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
        if Self.showsMusic(app) {
            ArtworkView(size: app.panel.hasNotch ? 20 : 16, cornerRadius: 5)
        } else if let meeting = Self.upcomingMeeting(app) {
            MeetingBadge(meeting: meeting, now: app.agenda.now)
        }
    }

    @ViewBuilder
    private var trailingStatus: some View {
        HStack(spacing: 7) {
            if Self.showsMusic(app), let meeting = Self.upcomingMeeting(app) {
                MeetingBadge(meeting: meeting, now: app.agenda.now)
            }
            if Self.showsVPN(app), let active = app.vpn.active {
                Image(systemName: active.status == .connected ? "lock.shield.fill" : "lock.shield")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.active)
                    .symbolEffect(.pulse, isActive: active.status == .connecting)
                    .help(Text(active.name))
            }
            if Self.showsMusic(app) {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: true)
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct MeetingBadge: View {
    let meeting: AgendaItem
    let now: Date

    var body: some View {
        let minutes = max(0, Int(meeting.start.timeIntervalSince(now) / 60))
        let happening = meeting.isHappening(at: now)
        HStack(spacing: 5) {
            Image(systemName: happening ? "video.fill" : "calendar")
                .foregroundStyle(Theme.accent)
            Text(happening ? String(localized: "now") : String(localized: "\(minutes) min"))
                .monospacedDigit()
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(.white)
    }
}
