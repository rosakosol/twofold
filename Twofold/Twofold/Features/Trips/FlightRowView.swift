//
//  FlightRowView.swift
//  Twofold
//
//  A flight tracked independently of any trip — same visual language as TripRowView.
//

import SwiftUI

struct FlightRowView: View {
    let flight: Flight

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle().fill(flight.status.semanticColor.opacity(0.15))
                Image(systemName: flight.status.icon).foregroundStyle(flight.status.semanticColor)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(flight.countdownSummary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
                HStack(spacing: Theme.Spacing.xs) {
                    Text(flight.origin.displayCode)
                    Image(systemName: "arrow.right")
                    Text(flight.destination.displayCode)
                }
                .font(.headline)

                Text("\(flight.displayNumber)\(flight.scheduledOut.map { " · \($0.formatted(.dateTime.day().month(.abbreviated)))" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
            }

            Spacer()
            PillBadge(text: flight.status.displayLabel, tint: flight.status.semanticColor)
        }
        .padding(Theme.Spacing.sm)
    }
}
