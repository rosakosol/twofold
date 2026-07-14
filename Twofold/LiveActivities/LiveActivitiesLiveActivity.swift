//
//  LiveActivitiesLiveActivity.swift
//  LiveActivities
//
//  Real flight-tracking Live Activity (replaces the Xcode template's placeholder). Started/
//  updated/ended by LiveActivityManager in the main app; content-state also pushed server-side
//  via supabase/functions/_shared/apns.ts's sendLiveActivityUpdate so this stays live even when
//  the app is backgrounded.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct JourneyLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JourneyActivityAttributes.self) { context in
            JourneyLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let status = FlightStatus(rawValue: context.state.status)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    JourneyExpandedOriginView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    JourneyExpandedDestinationView(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    JourneyExpandedProgressView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    JourneyExpandedFooterView(context: context)
                }
            } compactLeading: {
                FlightIconWithProgressArc(icon: status?.icon ?? "airplane", status: status, progress: context.state.progress, size: 20)
            } compactTrailing: {
                Text(context.state.timeRemainingLabel)
                    .font(.caption2.monospacedDigit())
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            } minimal: {
                FlightIconWithProgressArc(icon: "airplane", status: status, progress: context.state.progress, size: 22)
            }
            .widgetURL(URL(string: "twofold://flight/\(context.attributes.flightID.uuidString)"))
            .keylineTint(LiveActivityPalette.color(for: status))
        }
    }
}

/// Compact/minimal Dynamic Island icon, ringed with a circular progress arc while the flight is
/// actively `.inAir` — scheduled/boarding/landed phases have no meaningful "percent of route
/// flown" to show, and the ring would just read as visual noise there. `.landingSoon` is already
/// near-full progress by definition, so the ring stays reserved for the one phase it's actually
/// informative in.
private struct FlightIconWithProgressArc: View {
    let icon: String
    let status: FlightStatus?
    let progress: Double
    let size: CGFloat

    var body: some View {
        let tint = LiveActivityPalette.color(for: status)
        ZStack {
            if status == .inAir {
                Circle()
                    .stroke(tint.opacity(0.25), lineWidth: 2)
                Circle()
                    // A sliver floor keeps the arc visible (rather than invisible at 0%) right
                    // after takeoff, before `progress` has moved meaningfully off zero.
                    .trim(from: 0, to: max(0.03, min(1, progress)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    // Path trimming starts at the 3 o'clock position and runs clockwise;
                    // rotating -90° moves the start to 12 o'clock so the arc fills clockwise
                    // from the top, matching the reading direction of a clock/progress ring.
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: icon)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

extension JourneyActivityAttributes {
    fileprivate static var preview: JourneyActivityAttributes {
        JourneyActivityAttributes(
            flightID: UUID(),
            travelerName: "Erin",
            flightNumber: "QF9",
            airlineName: "Qantas",
            originCode: "MEL",
            originCity: "Melbourne",
            destinationCode: "SIN",
            destinationCity: "Singapore"
        )
    }
}

extension JourneyActivityAttributes.ContentState {
    fileprivate static var inAir: JourneyActivityAttributes.ContentState {
        JourneyActivityAttributes.ContentState(
            status: FlightStatus.inAir.rawValue,
            progress: 0.42,
            timeRemainingLabel: "Arrives in 3h 20m",
            isReunion: true,
            scheduledDeparture: .now.addingTimeInterval(-3600 * 3),
            scheduledArrival: .now.addingTimeInterval(3600 * 4),
            gateOrigin: "42",
            gateDestination: nil,
            lastUpdatedAt: .now
        )
    }

    fileprivate static var landingSoon: JourneyActivityAttributes.ContentState {
        JourneyActivityAttributes.ContentState(
            status: FlightStatus.landingSoon.rawValue,
            progress: 0.92,
            timeRemainingLabel: "Arrives in 22m",
            isReunion: true,
            scheduledDeparture: .now.addingTimeInterval(-3600 * 6),
            scheduledArrival: .now.addingTimeInterval(60 * 22),
            gateDestination: "B14",
            lastUpdatedAt: .now
        )
    }
}

#Preview("Lock Screen", as: .content, using: JourneyActivityAttributes.preview) {
    JourneyLiveActivityWidget()
} contentStates: {
    JourneyActivityAttributes.ContentState.inAir
    JourneyActivityAttributes.ContentState.landingSoon
}

#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: JourneyActivityAttributes.preview) {
    JourneyLiveActivityWidget()
} contentStates: {
    JourneyActivityAttributes.ContentState.inAir
}

#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: JourneyActivityAttributes.preview) {
    JourneyLiveActivityWidget()
} contentStates: {
    JourneyActivityAttributes.ContentState.inAir
}

#Preview("Dynamic Island Minimal", as: .dynamicIsland(.minimal), using: JourneyActivityAttributes.preview) {
    JourneyLiveActivityWidget()
} contentStates: {
    JourneyActivityAttributes.ContentState.inAir
}
