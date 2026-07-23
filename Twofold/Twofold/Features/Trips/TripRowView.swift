//
//  TripRowView.swift
//  Twofold
//

import SwiftUI

struct TripRowView: View {
    let trip: Trip
    let travelers: [Person]

    @Environment(AppModel.self) private var appModel

    private var dateRangeText: String {
        let format = Date.FormatStyle().day().month(.abbreviated)
        if Calendar.current.isDate(trip.departureDate, inSameDayAs: trip.arrivalDate) {
            return trip.departureDate.formatted(format)
        }
        return "\(trip.departureDate.formatted(format)) – \(trip.arrivalDate.formatted(format))"
    }

    var body: some View {
        // Mirrors `TripCarouselCard`'s layout exactly (single leading column of countdown badge +
        // avatars, city-to-city full width on its own line, date range and duration combined on
        // one secondary line) — this row and that peek card used to diverge (this one split
        // duration/flight-number/status into a separate trailing column, with avatars on their
        // own row below), which made a trip look formatted differently depending on whether you
        // saw it in the peek carousel or the expanded list, for no real reason.
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(spacing: Theme.Spacing.xs) {
                countdownBadge
                travelerAvatars
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(trip.origin.displayCity).lineLimit(1)
                    Image(systemName: "arrow.right")
                    Text(trip.destination.displayCity).lineLimit(1)
                }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: Theme.Spacing.xs) {
                    Text(dateRangeText)
                    Text("·")
                    Text(RelationshipMilestoneStats.tripDuration(trip))
                }
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
                .lineLimit(1)
            }
        }
        .padding(Theme.Spacing.sm)
    }

    /// Centered under `countdownBadge` (same fixed-width column) rather than a separate row below
    /// the whole trip summary — same pairing `TripCarouselCard` uses.
    private var travelerAvatars: some View {
        HStack(spacing: -8) {
            ForEach(travelers) { person in
                AvatarView(person: person, size: 20)
                    .overlay(Circle().stroke(Theme.cardBackground, lineWidth: 1.5))
            }
        }
        .frame(width: 38)
    }

    /// Replaces the old solo/paired avatar in this spot — days-to-go while the trip is still
    /// ahead, a "travelling now" state while it's actually underway (`trip.isActive`), and a
    /// simple done marker once it's over. A countdown wouldn't mean anything for the last two
    /// cases, so this isn't just "days-to-go, clamped to zero" for the whole row lifetime.
    @ViewBuilder
    private var countdownBadge: some View {
        VStack(spacing: 0) {
            if trip.departureDate > .now {
                let days = max(0, Calendar.current.dateComponents([.day], from: .now, to: trip.departureDate).day ?? 0)
                Text(days == 0 ? "🎉" : "\(days)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(days == 0 ? "Today" : (days == 1 ? "day" : "days"))
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
            } else if trip.isActive {
                Image(systemName: "airplane")
                    .font(.subheadline)
                    .foregroundStyle(Theme.skyBlue)
                Text("Now")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.leafGreen)
                Text("Done")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
            }
        }
        .frame(width: 38)
    }
}
