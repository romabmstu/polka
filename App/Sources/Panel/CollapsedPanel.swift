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

    /// Width of each wing beside the camera. Both wings are always the same
    /// width so the camera stays in the middle; they widen when the right one
    /// has to hold a meeting countdown next to the VPN shield.
    static func wingWidth(_ app: AppModel) -> CGFloat {
        let crowded = showsMusic(app) && upcomingMeeting(app) != nil && showsVPN(app)
        return crowded ? PanelMetrics.wideWingWidth : PanelMetrics.wingWidth
    }

    /// Room a wing keeps free: 14 pt from the outer edge and a few points
    /// short of the camera, so nothing slides underneath it.
    private static let wingInset: CGFloat = 12

    /// The waveform usually sits on the right, opposite the artwork. When the
    /// right wing also has to show a meeting countdown, it moves next to the
    /// artwork so neither wing overflows.
    private static func waveformBesideArtwork(_ app: AppModel) -> Bool {
        upcomingMeeting(app) != nil
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
            let wing = Self.wingWidth(app)
            HStack(spacing: 0) {
                leadingStatus
                    .frame(width: wing - Self.wingInset, alignment: .leading)
                    .padding(.leading, 14)
                Spacer(minLength: 0)
                trailingStatus
                    .frame(width: wing - Self.wingInset, alignment: .trailing)
                    .padding(.trailing, 14)
            }
            .frame(height: notchHeight)
        }
    }

    // MARK: Pill

    /// Width of the capsule for what it currently shows, so it stays small.
    static func pillWidth(_ app: AppModel) -> CGFloat {
        var width: CGFloat = 20
        if showsMusic(app) { width += 14 + 8 + 12 + 8 }
        if upcomingMeeting(app) != nil { width += 50 + 8 }
        if showsVPN(app) { width += 12 + 8 }
        return width == 20 ? 44 : width - 8
    }

    @ViewBuilder
    private var pillContent: some View {
        Group {
            if let flash = app.panel.flash {
                HStack(spacing: 6) {
                    Image(systemName: flash.symbol)
                    Text(flash.text).lineLimit(1)
                }
                .font(.system(size: 11.5, weight: .semibold))
            } else if Self.hasActivity(app) {
                HStack(spacing: 8) {
                    if Self.showsMusic(app) {
                        ArtworkView(size: 14, cornerRadius: 3.5)
                        Image(systemName: "waveform")
                            .font(.system(size: 10.5, weight: .bold))
                            .symbolEffect(.variableColor.iterative, isActive: true)
                    }
                    if let meeting = Self.upcomingMeeting(app) {
                        MeetingBadge(meeting: meeting, now: app.agenda.now, compact: true)
                    }
                    if Self.showsVPN(app), let active = app.vpn.active {
                        Image(systemName: active.status == .connected ? "lock.shield.fill" : "lock.shield")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Theme.active)
                            .symbolEffect(.pulse, isActive: active.status == .connecting)
                            .help(Text(active.name))
                    }
                }
            } else {
                // Idle: a small handle that hints "pull me down".
                Capsule()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 16, height: 3.5)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Status pieces

    @ViewBuilder
    private var leadingStatus: some View {
        if Self.showsMusic(app) {
            HStack(spacing: 7) {
                ArtworkView(size: app.panel.hasNotch ? 20 : 16, cornerRadius: 5)
                if Self.waveformBesideArtwork(app) { waveform }
            }
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
            if Self.showsMusic(app), !Self.waveformBesideArtwork(app) { waveform }
        }
        .fixedSize()
    }

    private var waveform: some View {
        Image(systemName: "waveform")
            .font(.system(size: 13, weight: .semibold))
            .symbolEffect(.variableColor.iterative, isActive: true)
            .foregroundStyle(.white)
    }
}

private struct MeetingBadge: View {
    let meeting: AgendaItem
    let now: Date
    var compact = false

    var body: some View {
        let minutes = max(0, Int(meeting.start.timeIntervalSince(now) / 60))
        let happening = meeting.isHappening(at: now)
        HStack(spacing: 5) {
            Image(systemName: happening ? "video.fill" : "calendar")
                .foregroundStyle(Theme.accent)
            Text(happening ? String(localized: "now") : String(localized: "\(minutes) min"))
                .monospacedDigit()
                .lineLimit(1)
        }
        .fixedSize()
        .font(.system(size: compact ? 10.5 : 11.5, weight: .semibold))
        .foregroundStyle(.white)
    }
}
