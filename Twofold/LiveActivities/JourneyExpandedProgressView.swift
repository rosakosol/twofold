//
//  JourneyExpandedProgressView.swift
//  LiveActivities
//

import ActivityKit
import SwiftUI
import WidgetKit

struct JourneyExpandedProgressView: View {
    let context: ActivityViewContext<JourneyActivityAttributes>

    private var status: FlightStatus? { FlightStatus(rawValue: context.state.status) }
    private var tint: Color { LiveActivityPalette.color(for: status) }

    /// Real departure/arrival `Date`s to anchor a `ProgressView(timerInterval:)` to, when both
    /// ends of the *current* leg are known — departure while not yet airborne, or arrival while
    /// en route. `ProgressView(timerInterval:)` is one of the same system-clock-driven primitives
    /// `journeyTimeRemainingText` relies on (see its own doc comment): it animates continuously
    /// on-device with no push needed, unlike the old `ProgressView(value: context.state.progress)`
    /// below, which only moved when a push happened to also fire for another reason.
    private var timerInterval: ClosedRange<Date>? {
        let state = context.state
        guard let departure = state.actualDeparture ?? state.estimatedDeparture ?? state.scheduledDeparture,
              let arrival = state.actualArrival ?? state.estimatedArrival ?? state.scheduledArrival,
              departure < arrival else { return nil }
        return departure...arrival
    }

    var body: some View {
        VStack(spacing: 4) {
            journeyTimeRemainingText(context.state)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let timerInterval {
                ProgressView(timerInterval: timerInterval, countsDown: false)
                    .tint(tint)
                    .labelsHidden()
                    .frame(maxWidth: 140)
            } else {
                ProgressView(value: context.state.progress)
                    .tint(tint)
                    .frame(maxWidth: 140)
            }
        }
        .padding(.horizontal, 8)
    }
}
