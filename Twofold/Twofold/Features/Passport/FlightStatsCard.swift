//
//  FlightStatsCard.swift
//  Twofold
//
//  The Stats tab's Flights card — replaces the old holographic "passport" cover look with the
//  same plain white `SectionCard` format `RelationshipStatsCard`/`TripStatsCard` already use, so
//  all three Stats tabs read as one consistent design rather than the flight tab looking like a
//  different app. Every figure still comes straight from `FlightStats`, never fabricated.
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
        SectionCard {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: Theme.Spacing.md) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ZStack {
                            Circle().fill(Theme.accent.opacity(0.15))
                            Image(systemName: "airplane").font(.subheadline).foregroundStyle(Theme.accent)
                        }
                        .frame(width: 32, height: 32)
                        Text("Flight Stats")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 0)
                    }

                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        heroStat(label: "Flights", value: "\(stats.flightCount)")
                        heroStat(label: "Distance", value: MeasurementPreference.distanceLabel(km: stats.totalDistanceKm))
                        heroStat(label: "Flight Time", value: FlightStats.duration(stats.totalFlightTime))
                    }
                    .frame(maxWidth: .infinity)

                    Divider()

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.sm), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                        StatTile(icon: "building.2.fill", label: "Airports", value: "\(stats.airports.count)", chip: .blue)
                        StatTile(icon: "airplane.circle.fill", label: "Airlines", value: "\(stats.airlines.count)", chip: .blue)
                        StatTile(icon: "globe.americas.fill", label: "Countries", value: "\(stats.countries.count)", chip: .green)
                        StatTile(icon: "globe.desk.fill", label: "Long Haul", value: "\(stats.longHaulCount)", chip: .indigo)
                        StatTile(icon: "house.fill", label: "Domestic", value: "\(stats.domesticCount)", chip: .violet)
                        StatTile(icon: "airplane.departure", label: "International", value: "\(stats.internationalCount)", chip: .coral)
                    }

                    if let onShowAllStats {
                        Button(action: onShowAllStats) {
                            HStack {
                                Text("All Flight Stats")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                            }
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, 12)
                            .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let onShare {
                    StatsShareButton(label: "Share flight stats", action: onShare)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heroStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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
