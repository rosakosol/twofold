//
//  PassportShareCard.swift
//  Twofold
//
//  The shareable Flight Stats image — reuses `FlightStatsCard` directly (same
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
        .background(Theme.backgroundGradient)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.shareCard, style: .continuous))
        // Pinned, because this renders to a fixed-size image that leaves the device: it should
        // look the same to whoever receives it rather than reflowing to the sender's text size.
        .dynamicTypeSize(.large)
    }
}

#Preview {
    PassportShareCard(stats: FlightStats(flights: MockData.trips.flatMap(\.flights), couple: MockData.couple))
        .padding()
        .background(Color.black)
}
