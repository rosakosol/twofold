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
                            Circle().fill(Theme.skyBlueText.opacity(0.15))
                            Image(systemName: "suitcase.fill").font(.subheadline).foregroundStyle(Theme.skyBlueText)
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
                            tint: Theme.leafGreenText
                        )
                        milestoneTile(
                            icon: "arrow.down.left",
                            label: "Shortest Trip",
                            value: stats.shortestTrip.map { RelationshipMilestoneStats.tripDuration($0) } ?? "—",
                            detail: stats.shortestTrip?.destination.displayCity,
                            tint: Theme.leafGreenText
                        )
                        milestoneTile(
                            icon: "mappin.and.ellipse",
                            label: "Top Destination",
                            value: stats.topDestination?.name ?? "—",
                            detail: stats.topDestination.map { $0.count == 1 ? "1 trip" : "\($0.count) trips" },
                            tint: Theme.skyBlueText
                        )
                        milestoneTile(icon: "heart.fill", label: "Reunion Trips", value: "\(stats.reunionCount)", tint: Theme.heartRedText)
                        milestoneTile(icon: "calendar.badge.clock", label: "Upcoming", value: "\(stats.upcomingCount)", tint: .orange)
                        milestoneTile(icon: "checkmark.circle.fill", label: "Completed", value: "\(stats.pastCount)", tint: .purple)
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
                            .foregroundStyle(Theme.skyBlueText)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, 12)
                            .background(Theme.skyBlueText.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
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
                // `.lineLimit(1)` here matters as much as the value/detail reservation below —
                // without it, a longer label ("Top Destination") wraps to 2 lines while a shorter
                // row-neighbor ("Reunion Trips") stays on 1, leaving the two tiles in that row
                // different heights despite the value/detail lines already being reserved
                // consistently (see `RelationshipStatsCard.milestoneTile`'s identical fix).
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.subtleInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                // Always reserve the detail line's height (even when there's no detail) so every
                // tile in the grid ends up the same height — same fix `RelationshipStatsCard`'s
                // own `milestoneTile` already applies. Without this, a tile with a detail (e.g.
                // "Top Destination") is a line taller than its row-sibling without one (e.g.
                // "Reunion Trips"), so the two don't line up.
                Text(detail ?? " ")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
                    .lineLimit(1)
                    .opacity(detail == nil ? 0 : 1)
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
