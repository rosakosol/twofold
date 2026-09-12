//
//  StatsShareButton.swift
//  Twofold
//
//  The circular share button on the Passport stat cards. Extracted because `TripStatsCard`,
//  `FlightStatsCard` and `RelationshipStatsCard` each carried a byte-identical copy, so the
//  off-centre glyph below was one bug in three places and would have been fixed in two of them.
//

import SwiftUI

struct StatsShareButton: View {
    /// Spoken label — "Share trip stats" and so on. Required rather than defaulted, because the
    /// three cards sit on one screen and "Share" three times tells a VoiceOver user nothing.
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.subtleInk)
                // `square.and.arrow.up` is not centred inside its own layout box. Measured at
                // 15pt semibold: an 18×22 box with the ink spanning y 3…20, so three points of
                // air above the arrow and one below the tray. Centring the *box* therefore hangs
                // the glyph a point low inside the circle, which is what reads as "not centred".
                .offset(y: -1)
                // A square frame, not `.padding(8)`. That box is taller than it is wide (22 vs
                // 18), so padding it evenly gave a 34×38 container — and `Circle()` insets to the
                // smaller side, leaving the circle floating in two points of slack it had no
                // reason to have. 34 keeps the drawn circle exactly the size it already was.
                .frame(width: 34, height: 34)
                .background(Theme.backgroundGradient, in: Circle())
        }
        .accessibilityLabel(label)
    }
}

#Preview {
    HStack(spacing: Theme.Spacing.md) {
        StatsShareButton(label: "Share trip stats") {}
        StatsShareButton(label: "Share flight stats") {}
    }
    .padding()
    .background(Theme.cardBackground)
}
