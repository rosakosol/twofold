//
//  TripStatsShareCard.swift
//  Twofold
//
//  The shareable Trip Stats image — reuses `TripStatsCard` directly (same white `SectionCard`
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
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

#Preview {
    TripStatsShareCard(stats: TripStats(trips: MockData.trips))
        .padding()
        .background(Color.black)
}
