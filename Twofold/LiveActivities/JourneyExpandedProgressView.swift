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

    var body: some View {
        VStack(spacing: 4) {
            Text(context.state.timeRemainingLabel)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            ProgressView(value: context.state.progress)
                .tint(tint)
                .frame(maxWidth: 140)
        }
        .padding(.horizontal, 8)
    }
}
