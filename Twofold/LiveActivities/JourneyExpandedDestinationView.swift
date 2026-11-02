//
//  JourneyExpandedDestinationView.swift
//  LiveActivities
//

import ActivityKit
import SwiftUI
import WidgetKit

struct JourneyExpandedDestinationView: View {
    let context: ActivityViewContext<JourneyActivityAttributes>

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(context.attributes.destinationCode)
                .font(.title3.weight(.bold))
            if let arrival = context.state.actualArrival ?? context.state.estimatedArrival ?? context.state.scheduledArrival {
                // The airport's own time, like the boarding pass — see `FlightLocalTime`.
                Text(arrival, format: FlightLocalTime.timeStyle(context.attributes.destinationTimeZoneID))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let gate = context.state.gateDestination {
                Text("Gate \(gate)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let baggageClaim = context.state.baggageClaim {
                Text("Baggage \(baggageClaim)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.trailing, 16)
    }
}
