//
//  JourneyExpandedOriginView.swift
//  LiveActivities
//

import ActivityKit
import SwiftUI
import WidgetKit

struct JourneyExpandedOriginView: View {
    let context: ActivityViewContext<JourneyActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(context.attributes.originCode)
                .font(.title3.weight(.bold))
            if let departure = context.state.actualDeparture ?? context.state.estimatedDeparture ?? Optional(context.state.scheduledDeparture) {
                Text(departure, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let gate = context.state.gateOrigin {
                Text("Gate \(gate)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
