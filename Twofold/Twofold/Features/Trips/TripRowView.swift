//
//  TripRowView.swift
//  Twofold
//
//  A trip on Travel (docs/TWOFOLD_DESIGN.md, section 6): the 64pt countdown tile, then the route,
//  the dates and who is going. The peek carousel's card is this same row in card chrome
//  (`TripCarouselCard`), so a trip looks the same whichever of the two you see it in.
//

import SwiftUI

struct TripRowView: View {
    let trip: Trip
    let travelers: [Person]

    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// "30 Sep to 14 Oct", or the one date for a same-day trip.
    private var dateRangeText: String {
        let format = Date.FormatStyle().day().month(.abbreviated)
        if Calendar.current.isDate(trip.departureDate, inSameDayAs: trip.arrivalDate) {
            return trip.departureDate.formatted(format)
        }
        return "\(trip.departureDate.formatted(format)) to \(trip.arrivalDate.formatted(format))"
    }

    /// Tile beside the text, or above it at accessibility sizes, where the tile has grown to take
    /// half the row and the route and dates were left a few letters each.
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.md))
    }

    var body: some View {
        rowLayout {
            TripCountdownTile(trip: trip, isNextReunion: trip.id == appModel.travel.nextReunionTripID)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(trip.origin.displayCity) to \(trip.destination.displayCity)")
                    .font(.body.bold())
                    .foregroundStyle(Theme.textPrimary)
                    // One clean line at normal sizes; at accessibility sizes shrinking back down
                    // would defeat the setting, so the route wraps instead.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)

                Text("\(dateRangeText), \(RelationshipMilestoneStats.tripDuration(trip))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

                if !travelers.isEmpty {
                    HStack(spacing: -6) {
                        ForEach(travelers) { person in
                            AvatarView(person: person, size: 22)
                                .overlay(Circle().stroke(Theme.surface, lineWidth: 1.5))
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.sm)
        // One VoiceOver read ("22 days, Rome to Melbourne, 30 Sep to 14 Oct, 14 days") rather than
        // a swipe per piece.
        .accessibilityElement(children: .combine)
    }
}
