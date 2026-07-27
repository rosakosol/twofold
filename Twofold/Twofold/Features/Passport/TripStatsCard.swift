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

    var body: some View {
        SectionCard {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: Theme.Spacing.md) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ZStack {
                            Circle().fill(Theme.skyBlue.opacity(0.15))
                            Image(systemName: "suitcase.fill").font(.subheadline).foregroundStyle(Theme.skyBlue)
                        }
                        .frame(width: 32, height: 32)
                        Text("Trip Stats")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
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
                        milestoneTile(
                            icon: "arrow.up.right",
                            label: "Longest Trip",
                            value: stats.longestTrip.map { RelationshipMilestoneStats.tripDuration($0) } ?? "—",
                            detail: stats.longestTrip?.destination.displayCity,
                            tint: Theme.leafGreen
                        )
                        milestoneTile(
                            icon: "arrow.down.left",
                            label: "Shortest Trip",
                            value: stats.shortestTrip.map { RelationshipMilestoneStats.tripDuration($0) } ?? "—",
                            detail: stats.shortestTrip?.destination.displayCity,
                            tint: Theme.leafGreen
                        )
                        milestoneTile(
                            icon: "mappin.and.ellipse",
                            label: "Top Destination",
                            value: stats.topDestination?.name ?? "—",
                            detail: stats.topDestination.map { $0.count == 1 ? "1 trip" : "\($0.count) trips" },
                            tint: Theme.skyBlue
                        )
                        milestoneTile(icon: "heart.fill", label: "Reunion Trips", value: "\(stats.reunionCount)", tint: Theme.heartRed)
                        milestoneTile(icon: "calendar.badge.clock", label: "Upcoming", value: "\(stats.upcomingCount)", tint: .orange)
                        milestoneTile(icon: "checkmark.circle.fill", label: "Completed", value: "\(stats.pastCount)", tint: .purple)
                    }
                }

                if let onShare {
                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.subtleInk)
                            .padding(8)
                            .background(Theme.backgroundGradient, in: Circle())
                    }
                    .accessibilityLabel("Share trip stats")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Forces the light-mode look regardless of system appearance — see
        // `RelationshipStatsCard`'s identical `.colorScheme(.light)` for why.
        .colorScheme(.light)
    }

    private func heroStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.subtleInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func milestoneTile(icon: String, label: String, value: String, detail: String? = nil, tint: Color) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().fill(tint.opacity(0.15))
                Image(systemName: icon).font(.subheadline).foregroundStyle(tint)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.subtleInk)
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(Theme.subtleInk)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.sm)
        .themedCardBackground(cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    TripStatsCard(stats: TripStats(trips: MockData.trips))
        .padding()
        .background(Theme.backgroundGradient)
}
