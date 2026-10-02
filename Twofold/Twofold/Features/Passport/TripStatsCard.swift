//
//  TripStatsCard.swift
//  Twofold
//
//  The Stats tab's Trips card — deliberately styled like `RelationshipStatsCard` (plain white
//  `SectionCard`, hero row + milestone-tile grid) rather than `PassportView`'s holographic
//  blue/gold "passport" look, since this is trip-shaped data (how many, how far, how long,
//  where), not the flight-specific passport metaphor the card below it on the Flights tab uses.
//

import SwiftUI

struct TripStatsCard: View {
    let stats: TripStats
    /// Inline share affordance in the card's own corner, same placement/behavior as
    /// `RelationshipStatsCard.onShare`/`FlightStatsCard.onShare` — nil hides the button (the
    /// share card's own preview has nothing to open).
    var onShare: (() -> Void)?
    /// Set only when reached from the Stats tab (not the share-card preview) — pushes the full
    /// scoped breakdown, mirroring `FlightStatsCard.onShowAllStats`.
    var onShowAllStats: (() -> Void)?

    var body: some View {
        SectionCard {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: Theme.Spacing.md) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ZStack {
                            Circle().fill(Theme.accent.opacity(0.15))
                            Image(systemName: "suitcase.fill").font(.subheadline).foregroundStyle(Theme.accent)
                        }
                        .frame(width: 32, height: 32)
                        Text("Trip Stats")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 0)
                    }

                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        heroStat(label: "Total Trips", value: "\(stats.totalTrips)")
                        heroStat(label: "Distance", value: MeasurementPreference.distanceLabel(km: stats.totalDistanceKm))
                        heroStat(label: "Trip Days", value: "\(stats.totalDays)")
                    }
                    .frame(maxWidth: .infinity)

                    Divider()

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.sm), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                        StatTile(
                            icon: "arrow.up.right",
                            label: "Longest Trip",
                            value: stats.longestTrip.map { RelationshipMilestoneStats.tripDuration($0) } ?? "—",
                            detail: stats.longestTrip?.destination.displayCity,
                            chip: .green
                        )
                        StatTile(
                            icon: "arrow.down.left",
                            label: "Shortest Trip",
                            value: stats.shortestTrip.map { RelationshipMilestoneStats.tripDuration($0) } ?? "—",
                            detail: stats.shortestTrip?.destination.displayCity,
                            chip: .green
                        )
                        StatTile(
                            icon: "mappin.and.ellipse",
                            label: "Top Destination",
                            value: stats.topDestination?.name ?? "—",
                            detail: stats.topDestination.map { $0.count == 1 ? "1 trip" : "\($0.count) trips" },
                            chip: .blue
                        )
                        StatTile(icon: "heart.fill", label: "Reunion Trips", value: "\(stats.reunionCount)", chip: .coral)
                        StatTile(icon: "calendar.badge.clock", label: "Upcoming", value: "\(stats.upcomingCount)", chip: .indigo)
                        StatTile(icon: "checkmark.circle.fill", label: "Completed", value: "\(stats.pastCount)", chip: .violet)
                    }

                    // Identical to `FlightStatsCard`'s own drill-in row — same tinted pill, same
                    // weights, same metrics. These two cards sit one above the other on the Stats
                    // tab, so any difference between them reads as one of them being wrong.
                    if let onShowAllStats {
                        Button(action: onShowAllStats) {
                            HStack {
                                Text("All Trip Stats")
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
                    StatsShareButton(label: "Share trip stats", action: onShare)
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
    TripStatsCard(stats: TripStats(trips: MockData.trips))
        .padding()
        .background(Theme.backgroundGradient)
}
