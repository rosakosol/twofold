//
//  TripCountdownTile.swift
//  Twofold
//

import SwiftUI

/// The 64pt tile that leads a trip on Travel (docs/TWOFOLD_DESIGN.md, section 6): days to go while
/// the trip is ahead, "Now" while it is under way, "Done" once it is over.
///
/// The next reunion's tile is coral with white text, because coral is the two of you and that trip
/// is the one being counted down to. Every other tile is neutral.
struct TripCountdownTile: View {
    let trip: Trip
    var isNextReunion: Bool = false

    @ScaledMetric(relativeTo: .title2) private var size: CGFloat = 64

    private var foreground: Color { isNextReunion ? Theme.onFill : Theme.textPrimary }
    private var secondary: Color { isNextReunion ? Theme.onFill.opacity(0.92) : Theme.textSecondary }

    var body: some View {
        VStack(spacing: 0) {
            if trip.departureDate > .now {
                let days = max(0, TimeMath.daysUntil(trip.departureDate))
                if days == 0 {
                    Text("Today")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(foreground)
                } else {
                    Text("\(days)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(foreground)
                        .minimumScaleFactor(0.6)
                    Text(days == 1 ? "day" : "days")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(secondary)
                }
            } else if trip.isActive {
                Image(systemName: "airplane")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isNextReunion ? Theme.onFill : Theme.accent)
                    .accessibilityHidden(true)
                Text("Now")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondary)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.success)
                    .accessibilityHidden(true)
                Text("Done")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondary)
            }
        }
        .lineLimit(1)
        .frame(width: size, height: size)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.image, style: .continuous)
            if isNextReunion {
                shape.fill(Theme.coralGradient).overlay { BrandHighlight() }.clipShape(shape)
            } else {
                shape.fill(Theme.raised).overlay { shape.strokeBorder(Theme.line, lineWidth: 1) }
            }
        }
    }
}
