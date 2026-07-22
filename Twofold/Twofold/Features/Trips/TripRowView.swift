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

    private var statusBadge: (text: String, tint: Color)? {
        guard let flight = trip.mostRelevantFlight else { return nil }
        switch flight.status {
        case .arrived, .landed: return ("Landed", Theme.leafGreen)
        case .boarding: return ("Boarding", Theme.skyBlue)
        case .departed: return ("Departed", Theme.skyBlue)
        case .inAir: return ("In the air", Theme.skyBlue)
        case .landingSoon: return ("Landing soon", Theme.heartRed)
        case .scheduled: return ("Upcoming", Theme.subtleInk)
        case .delayed: return ("Delayed", Theme.heartRed)
        case .cancelled, .diverted: return ("Disrupted", Theme.heartRed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                countdownBadge

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(trip.origin.city)
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                        Text(trip.destination.city)
                            .lineLimit(1)
                    }
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                    HStack(spacing: Theme.Spacing.xs) {
                        Text(dateRangeText)
                        if let flight = trip.mostRelevantFlight {
                            Text(trip.flights.count > 1 ? "· \(flight.flightNumber) +\(trip.flights.count - 1)" : "· \(flight.flightNumber)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(RelationshipMilestoneStats.tripDuration(trip))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    if let statusBadge {
                        PillBadge(text: statusBadge.text, tint: statusBadge.tint)
                    }
                }
            }

            HStack(spacing: -8) {
                ForEach(travelers) { person in
                    AvatarView(person: person, size: 22)
                        .overlay(Circle().stroke(Theme.cardBackground, lineWidth: 1.5))
                }
            }
        }
        .padding(Theme.Spacing.sm)
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
                    .font(.system(size: days == 0 ? 20 : 20, weight: .bold, design: .rounded))
                Text(days == 0 ? "Today" : (days == 1 ? "day" : "days"))
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
            } else if trip.isActive {
                Image(systemName: "airplane")
                    .font(.title3)
                    .foregroundStyle(Theme.skyBlue)
                Text("Now")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.leafGreen)
                Text("Done")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
            }
        }
        .frame(width: 44)
    }
}
