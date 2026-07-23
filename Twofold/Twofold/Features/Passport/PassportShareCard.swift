//
//  PassportShareCard.swift
//  Twofold
//
//  The shareable Flight Stats image — reuses `FlightStatsCard` directly (same white
//  `SectionCard` look the in-app Stats tab shows) with a brand mark on top, mirroring how
//  `RelationshipStatsShareCard`'s classic layout reuses `RelationshipStatsCard`. Replaces the old
//  holographic "passport" cover-page treatment, which read as a different app design language
//  than the rest of Stats. Every figure still comes straight from `FlightStats`, never fabricated.
//

import SwiftUI

struct PassportShareCard: View {
    let stats: FlightStats

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            TwofoldBrandMark(color: Theme.ink, size: 24, textStyle: .title3)
            FlightStatsCard(stats: stats)
        }
        .padding(Theme.Spacing.sm)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

#Preview {
    PassportShareCard(stats: FlightStats(trips: MockData.trips, couple: MockData.couple))
        .padding()
        .background(Color.black)
}
