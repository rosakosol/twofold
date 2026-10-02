//
//  TripStatsCard.swift
//  Twofold
//
//  The Stats tab's Trips section: a summary on `heroBlueGreen` (docs/TWOFOLD_DESIGN.md, section 6)
//  over a grid of stat tiles and the "All trip stats" row.
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
        VStack(spacing: Theme.Spacing.md) {
            // The trips summary on `heroBlueGreen` (section 6, Stats), with its share button.
            StatsHeroCard(gradient: Theme.heroBlueGreen, shareLabel: "Share trip stats", onShare: onShare) {
                Label("Trip stats", systemImage: "suitcase.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    StatsHeroNumber(label: "Total trips", value: "\(stats.totalTrips)")
                    StatsHeroNumber(label: "Distance", value: MeasurementPreference.distanceLabel(km: stats.totalDistanceKm))
                    StatsHeroNumber(label: "Trip days", value: "\(stats.totalDays)")
                }
                .frame(maxWidth: .infinity)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.sm), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                StatTile(
                    icon: "arrow.up.right",
                    label: "Longest trip",
                    value: stats.longestTrip.map { RelationshipMilestoneStats.tripDuration($0) } ?? "—",
                    detail: stats.longestTrip?.destination.displayCity,
                    chip: .green
                )
                StatTile(
                    icon: "arrow.down.left",
                    label: "Shortest trip",
                    value: stats.shortestTrip.map { RelationshipMilestoneStats.tripDuration($0) } ?? "—",
                    detail: stats.shortestTrip?.destination.displayCity,
                    chip: .indigo
                )
                StatTile(
                    icon: "mappin.and.ellipse",
                    label: "Top destination",
                    value: stats.topDestination?.name ?? "—",
                    detail: stats.topDestination.map { $0.count == 1 ? "1 trip" : "\($0.count) trips" },
                    chip: .blue
                )
                StatTile(icon: "heart.fill", label: "Reunion trips", value: "\(stats.reunionCount)", chip: .coral)
                StatTile(icon: "calendar.badge.clock", label: "Upcoming", value: "\(stats.upcomingCount)", chip: .indigo)
                StatTile(icon: "checkmark.circle.fill", label: "Completed", value: "\(stats.pastCount)", chip: .violet)
            }

            if let onShowAllStats {
                AllStatsRow(title: "All trip stats", action: onShowAllStats)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The drill-in row under a Stats section (section 6: "All trip stats" in accent). Shared by the
/// Trips and Flights cards, which sit one above the other, so any difference would read as a bug.
struct AllStatsRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 48)
            .themedCardBackground(cornerRadius: Theme.Radius.tile)
        }
        .buttonStyle(.plain)
    }
}
