//
//  TripRowView.swift
//  Twofold
//

import SwiftUI

struct TripRowView: View {
    let trip: Trip
    let travelers: [Person]

    private var travelerNames: String {
        travelers.map(\.name).joined(separator: " & ")
    }

    private var statusBadge: (text: String, tint: Color)? {
        guard let flight = trip.flight else { return nil }
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
        HStack(spacing: Theme.Spacing.md) {
            if travelers.count > 1 {
                HStack(spacing: -12) {
                    ForEach(travelers) { person in
                        AvatarView(person: person, size: 36)
                            .overlay(Circle().stroke(Theme.cardBackground, lineWidth: 2))
                    }
                }
            } else {
                AvatarView(person: travelers[0], size: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(trip.notes ?? "\(travelerNames) flies to \(trip.destination.city)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
                HStack(spacing: Theme.Spacing.xs) {
                    Text(trip.origin.iataCode ?? trip.origin.city)
                    Image(systemName: "arrow.right")
                    Text(trip.destination.iataCode ?? trip.destination.city)
                }
                .font(.headline)

                HStack(spacing: Theme.Spacing.xs) {
                    Text(trip.departureDate, format: .dateTime.day().month(.abbreviated).year())
                    if let flight = trip.flight {
                        Text("· \(flight.flightNumber)")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
            }

            Spacer()

            if let statusBadge {
                PillBadge(text: statusBadge.text, tint: statusBadge.tint)
            }
        }
        .padding(Theme.Spacing.sm)
    }
}
