//
//  TimelineRow.swift
//  Twofold
//

import SwiftUI

struct TimelineRow: View {
    let event: FlightTimelineEvent
    var isLast: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: event.isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(event.isComplete ? Theme.leafGreen : Theme.subtleInk.opacity(0.4))

            VStack(alignment: .leading, spacing: 2) {
                Text(event.kind.rawValue)
                    .font(.subheadline.weight(event.isComplete ? .semibold : .regular))
                    .foregroundStyle(event.isComplete ? Theme.ink : Theme.subtleInk)
            }

            Spacer()

            Text(event.time, format: .dateTime.hour().minute())
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
        }
    }
}
