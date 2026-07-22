//
//  TripsCarouselCards.swift
//  Twofold
//
//  Compact, fixed-width cards for the Trips tab's peek-height browse sheet — floating directly
//  over the full-screen globe, unlike `TripRowView`/`FlightRowView` which are plain backgroundless
//  rows built for a `List`'s own chrome. Purpose-built rather than retrofitting those (which stay
//  exactly as they are for the sheet's expanded `.large`-detent list), so a little of their
//  countdown/summary logic is duplicated here in compact form rather than shared — small enough,
//  and each view's real job (fixed-width floating card vs. full-width list row) is different
//  enough, that forcing one shared implementation would cost more than the duplication does.
//

import SwiftUI

private let carouselCardWidth: CGFloat = 300

struct TripCarouselCard: View {
    let trip: Trip
    let travelers: [Person]

    private var dateRangeText: String {
        let format = Date.FormatStyle().day().month(.abbreviated)
        if Calendar.current.isDate(trip.departureDate, inSameDayAs: trip.arrivalDate) {
            return trip.departureDate.formatted(format)
        }
        return "\(trip.departureDate.formatted(format)) – \(trip.arrivalDate.formatted(format))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                countdownBadge

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(trip.origin.city).lineLimit(1)
                        Image(systemName: "arrow.right")
                        Text(trip.destination.city).lineLimit(1)
                    }
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                    Text(dateRangeText)
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                }

                Spacer(minLength: 0)
            }

            HStack {
                HStack(spacing: -8) {
                    ForEach(travelers) { person in
                        AvatarView(person: person, size: 20)
                            .overlay(Circle().stroke(Theme.cardBackground, lineWidth: 1.5))
                    }
                }
                Spacer()
                Text(RelationshipMilestoneStats.tripDuration(trip))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(width: carouselCardWidth, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }

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

struct FlightCarouselCard: View {
    let flight: Flight

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                AirlineLogoView(url: flight.displayLogoURL, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(flight.origin.displayCode)
                        Image(systemName: "arrow.right")
                        Text(flight.destination.displayCode)
                    }
                    .font(.subheadline.weight(.semibold))
                    Text(flight.countdownSummary)
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            HStack {
                Text([flight.airlineName, flight.displayNumber].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
                    .lineLimit(1)
                Spacer()
                PillBadge(text: flight.status.displayLabel, tint: flight.status.semanticColor)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(width: carouselCardWidth, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}

#Preview {
    ZStack {
        Color.blue.ignoresSafeArea()
        VStack {
            TripCarouselCard(trip: MockData.reunionTrip, travelers: [MockData.rosa, MockData.dara])
            FlightCarouselCard(flight: MockData.activeFlight)
        }
    }
}
