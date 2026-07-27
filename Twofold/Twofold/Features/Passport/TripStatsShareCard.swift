//
//  TripStatsShareCard.swift
//  Twofold
//
//  The shareable Trip Stats image — reuses `TripStatsCard` directly (same `SectionCard`
//  look the in-app Stats tab shows) with a brand mark on top, mirroring exactly how
//  `PassportShareCard` wraps `FlightStatsCard`. Every figure still comes straight from
//  `TripStats`, never fabricated.
//

import SwiftUI

struct TripStatsShareCard: View {
    let stats: TripStats

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            TwofoldBrandMark(color: Theme.ink, size: 24, textStyle: .title3)
            TripStatsCard(stats: stats)
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.backgroundGradient)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        // Forces the light-mode look for the whole shareable image (brand mark, background
        // gradient, and the embedded `TripStatsCard`) regardless of system appearance — same
        // as `TripStatsCard`'s own `.colorScheme(.light)`, applied here too so this card's own
        // background/brand mark don't stay dark while the card floating on them goes light.
        .colorScheme(.light)
    }
}

#Preview {
    TripStatsShareCard(stats: TripStats(trips: MockData.trips))
        .padding()
        .background(Color.black)
}
