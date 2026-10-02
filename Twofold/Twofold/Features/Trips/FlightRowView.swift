//
//  FlightRowView.swift
//  Twofold
//
//  A flight tracked independently of any trip — same visual language as TripRowView.
//

import SwiftUI

struct FlightRowView: View {
    let flight: Flight

    /// Was a fixed 44, the largest `AirlineLogoView` anywhere and visibly too big in the panel.
    /// 32 is what the airline picker and flight confirmation rows use, and it sits inside the 38pt
    /// lane `TripRowView` gives its countdown and avatars — those rows are directly beside this one
    /// in the same list, and this file's premise is that the two look alike.
    ///
    /// Scaled, because it was also the only leading element in that panel that did not grow with
    /// Dynamic Type: oversized at default sizes and undersized at large ones.
    @ScaledMetric(relativeTo: .subheadline) private var logoSize: CGFloat = 32

    /// Still to arrive: departing, in the air, or landing.
    private var isAhead: Bool { (flight.bestArrival ?? flight.scheduledArrival) > .now }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            AirlineLogoView(url: flight.displayLogoURL, size: logoSize, fallbackCode: flight.airlineCode)

            VStack(alignment: .leading, spacing: 2) {
                // "Departs in 24d 8h" in accent while it is ahead, "Arrived 10 days ago" in
                // textSecondary once it is behind you (section 6, Travel).
                Text(flight.countdownSummary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isAhead ? Theme.accent : Theme.textSecondary)
                    .lineLimit(1)
                HStack(spacing: Theme.Spacing.xs) {
                    Text(flight.origin.displayCode)
                    Image(systemName: "arrow.right").accessibilityLabel("to")
                    Text(flight.destination.displayCode)
                }
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

                Text("\([flight.airlineName, flight.displayNumber].compactMap { $0 }.joined(separator: " "))\(flight.scheduledOut.map { " · \($0.formatted(.dateTime.day().month(.abbreviated)))" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()
            StatusPill(flight: flight)
        }
        .padding(Theme.Spacing.sm)
        // Without this, the row's own `Spacer()` and other empty space don't count as part of
        // the tappable area when this is wrapped in a plain-style `Button` (`TripsListView`'s
        // `flightRow(_:)`) — only the actually-rendered content (logo/text/badge) responded to a
        // tap, so pressing anywhere else in the row (e.g. the blank stretch next to the badge)
        // silently did nothing.
        .contentShape(Rectangle())
    }
}
