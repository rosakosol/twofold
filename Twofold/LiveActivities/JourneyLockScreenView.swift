//
//  JourneyLockScreenView.swift
//  LiveActivities
//
//  The Lock Screen Live Activity: the traveller's photo and a line about them ("Alex is on the
//  way", "EK96 to Dubai"), a live countdown in the accent on the right, a progress bar with the
//  plane riding it, and both airports with their times underneath.
//
//  Worded for whoever holds the phone. Each device starts its own Live Activity and knows whether
//  its viewer is the one flying, so the traveller reads "You're on the way" and the person waiting
//  reads the traveller's name.
//
//  `LiveActivitySellView` (onboarding) draws a copy of this card; change the two together.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct JourneyLockScreenView: View {
    let context: ActivityViewContext<JourneyActivityAttributes>

    private var attributes: JourneyActivityAttributes { context.attributes }
    private var state: JourneyActivityAttributes.ContentState { context.state }
    private var status: FlightStatus? { FlightStatus(rawValue: state.status) }
    private var tint: Color { LiveActivityPalette.liveActivityAccent }

    private var departure: Date? { state.actualDeparture ?? state.estimatedDeparture ?? state.scheduledDeparture }
    private var arrival: Date? { state.actualArrival ?? state.estimatedArrival ?? state.scheduledArrival }

    private enum Phase { case beforeTakeOff, inAir, landed, cancelled, diverted }

    private var phase: Phase {
        switch status {
        case .cancelled: .cancelled
        case .diverted: .diverted
        case .landed, .arrived: .landed
        // Boarding is still at the gate, so it counts down to take-off rather than to landing.
        case .departed, .inAir, .landingSoon: .inAir
        default: .beforeTakeOff
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                WidgetAvatarView(
                    person: attributes.viewerIsTraveler ? .me : .partner,
                    name: attributes.travelerName,
                    size: 44
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                countdown
            }

            progressBar

            HStack {
                airport(code: attributes.originCode, time: departure)
                Spacer(minLength: 8)
                airport(code: attributes.destinationCode, time: arrival)
            }
        }
        .padding(18)
    }

    // MARK: - Wording

    private var headline: String {
        let name = attributes.travelerName
        let mine = attributes.viewerIsTraveler
        switch phase {
        case .cancelled: return String(localized: "Flight cancelled")
        case .diverted: return String(localized: "Flight diverted")
        case .landed: return mine ? String(localized: "You've landed") : String(localized: "\(name) has landed")
        case .inAir:
            // On a reunion the person waiting is who the flight is coming to.
            if state.isReunion {
                return mine
                    ? String(localized: "On the way to \(attributes.partnerName)")
                    : String(localized: "\(name) is on the way to you")
            }
            return mine ? String(localized: "You're on the way") : String(localized: "\(name) is on the way")
        case .beforeTakeOff:
            return mine ? String(localized: "You fly soon") : String(localized: "\(name) flies soon")
        }
    }

    /// "EK96 to Dubai". Past the content's stale date nothing has been heard for too long to stand
    /// behind (see `LiveActivityManager.staleDate`), so it says that instead.
    private var subtitle: String {
        if context.isStale { return String(localized: "Tap to refresh — may be out of date") }
        let destination = attributes.destinationCity ?? attributes.destinationCode
        return String(localized: "\(attributes.flightNumber) to \(destination)")
    }

    // MARK: - Countdown

    /// A date-anchored `Text`, so it ticks on the Lock Screen between pushes. Once its moment has
    /// passed it says what is happening instead, because a relative date counts back up again.
    @ViewBuilder
    private var countdown: some View {
        VStack(alignment: .trailing, spacing: 0) {
            switch phase {
            case .cancelled, .diverted:
                EmptyView()
            case .landed:
                bigValue(Text("Landed"))
                if let arrival { caption(Text(arrival, style: .time)) }
            case .inAir:
                if let arrival, arrival > .now {
                    bigValue(Text(arrival, style: .relative))
                    caption(Text("to landing"))
                } else {
                    bigValue(Text("Landing"))
                }
            case .beforeTakeOff:
                if let departure, departure > .now {
                    bigValue(Text(departure, style: .relative))
                    caption(Text("to take-off"))
                } else {
                    bigValue(Text(status == .boarding ? "Boarding" : "Soon"))
                }
            }
        }
        .opacity(context.isStale ? 0.5 : 1)
    }

    private func bigValue(_ text: Text) -> some View {
        text
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(tint)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func caption(_ text: Text) -> some View {
        text
            .font(.system(size: 15))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
    }

    // MARK: - Route

    private var progressBar: some View {
        GeometryReader { geo in
            let progress = phase == .landed ? 1 : min(1, max(0, state.progress))
            let x = geo.size.width * progress
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22)).frame(height: 4)
                Capsule().fill(tint).frame(width: max(4, x), height: 4)
                // Navy on the light accent: white on #6AA5F5 is about 2.4:1, under the 3:1 an icon
                // needs; navy is 7.6:1.
                Image(systemName: "airplane")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LiveActivityPalette.onAccent)
                    .frame(width: 26, height: 26)
                    .background(tint, in: Circle())
                    .position(x: min(max(13, x), geo.size.width - 13), y: geo.size.height / 2)
            }
            .frame(height: geo.size.height)
        }
        .frame(height: 26)
        .accessibilityHidden(true)
    }

    /// `time` is nil when the provider hasn't supplied any schedule for this leg yet: "—", never a
    /// made-up "now".
    private func airport(code: String, time: Date?) -> some View {
        HStack(spacing: 5) {
            Text(code)
                .font(.system(size: 17, weight: .semibold))
            Group {
                if let time {
                    Text(time, style: .time)
                } else {
                    Text("—")
                }
            }
            .font(.system(size: 17))
            .opacity(0.85)
        }
        .foregroundStyle(.white)
        .lineLimit(1)
    }
}
