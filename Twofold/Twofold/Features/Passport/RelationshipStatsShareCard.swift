//
//  RelationshipStatsShareCard.swift
//  Twofold
//
//  The shareable Relationship Stats image — reuses `RelationshipStatsCard` directly (same
//  `SectionCard` look the in-app Stats tab shows) with a brand mark on top, mirroring exactly how
//  `PassportShareCard`/`TripStatsShareCard` wrap their own in-app cards. Dropped the old photo-
//  story/gradient-background treatment (a different, bespoke layout the Trips/Flights share cards
//  never had) so all three Stats-tab share cards read as one consistent family — and, since
//  `RelationshipStatsCard` already supports both appearances, this picks up dark/light mode for
//  free rather than needing its own separate theming.
//

import SwiftUI

struct RelationshipStatsShareCard: View {
    let couple: Couple
    let stats: RelationshipMilestoneStats
    var showTripsChip = true
    var showReunionsChip = true
    var showMemoriesChip = true

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            TwofoldBrandMark(color: Theme.ink, size: 24, textStyle: .title3)
            RelationshipStatsCard(
                couple: couple,
                stats: stats,
                showTripsStat: showTripsChip,
                showReunionsStat: showReunionsChip,
                showMemoriesStat: showMemoriesChip
            )
        }
        // `RelationshipStatsCard` already carries its own `SectionCard` padding — this only
        // needs enough outer margin for the brand mark and the rounded-corner clip below, not a
        // second full padding pass stacked on top of that.
        .padding(Theme.Spacing.sm)
        .background(Theme.backgroundGradient)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

#Preview {
    RelationshipStatsShareCard(
        couple: MockData.couple,
        stats: RelationshipMilestoneStats(couple: MockData.couple, trips: MockData.trips, memories: MockData.memories)
    )
    .padding()
    .background(Color.black)
}
