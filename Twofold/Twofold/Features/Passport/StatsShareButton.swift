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
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
                // `square.and.arrow.up` is not centred inside its own layout box. Measured at
                // 15pt semibold: an 18×22 box with the ink spanning y 3…20, so three points of
                // air above the arrow and one below the tray. Centring the *box* therefore hangs
                // the glyph a point low inside the circle, which is what reads as "not centred".
                .offset(y: -1)
                // A square frame, not padding: the glyph's box is taller than it is wide, so even
                // padding gives an oval container and the circle floats in slack. 44pt is the
                // spec's circular nav button and the minimum tap target.
                .frame(width: 44, height: 44)
                .background(Theme.raised, in: Circle())
                .overlay { Circle().strokeBorder(Theme.line, lineWidth: 1) }
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
    .background(Theme.surface)
}
