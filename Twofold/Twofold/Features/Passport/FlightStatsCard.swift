//
//  FlightStatsCard.swift
//  Twofold
//
//  The Stats tab's Flights section: a summary on the `flight` gradient over a grid of stat tiles,
//  the same shape as the Relationship and Trips sections so the three read as one design. Every
//  figure comes straight from `FlightStats`.
//

import SwiftUI

struct FlightStatsCard: View {
    let stats: FlightStats
    /// Inline share affordance in the card's own corner, same placement/behavior as
    /// `RelationshipStatsCard.onShare` — nil hides the button (the share card's own preview has
    /// nothing to open).
    var onShare: (() -> Void)?
    /// Set only when reached from the Stats tab (not the share-card preview) — pushes the full
    /// scoped breakdown, same link the old passport card's "All Flight Stats" row opened.
    var onShowAllStats: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            // The flights summary on the `flight` gradient, the same shape as the Relationship and
            // Trips sections above it.
            StatsHeroCard(gradient: Theme.flight, shareLabel: "Share flight stats", onShare: onShare) {
                Label("Flight stats", systemImage: "airplane")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    StatsHeroNumber(label: "Flights", value: "\(stats.flightCount)")
                    StatsHeroNumber(label: "Distance", value: MeasurementPreference.distanceLabel(km: stats.totalDistanceKm))
                    StatsHeroNumber(label: "Flight time", value: FlightStats.duration(stats.totalFlightTime))
                }
                .frame(maxWidth: .infinity)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.sm), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                StatTile(icon: "building.2.fill", label: "Airports", value: "\(stats.airports.count)", chip: .blue)
                StatTile(icon: "airplane.circle.fill", label: "Airlines", value: "\(stats.airlines.count)", chip: .blue)
                StatTile(icon: "globe.americas.fill", label: "Countries", value: "\(stats.countries.count)", chip: .green)
                StatTile(icon: "globe.desk.fill", label: "Long haul", value: "\(stats.longHaulCount)", chip: .indigo)
                StatTile(icon: "house.fill", label: "Domestic", value: "\(stats.domesticCount)", chip: .violet)
                StatTile(icon: "airplane.departure", label: "International", value: "\(stats.internationalCount)", chip: .coral)
            }

            if let onShowAllStats {
                AllStatsRow(title: "All flight stats", action: onShowAllStats)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    FlightStatsCard(
        stats: FlightStats(flights: MockData.trips.flatMap(\.flights), couple: MockData.couple),
        onShowAllStats: {}
    )
        .padding()
        .background(Theme.backgroundGradient)
}
