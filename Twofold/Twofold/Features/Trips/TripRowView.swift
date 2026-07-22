//
//  TripRowView.swift
//  Twofold
//

import SwiftUI

struct TripRowView: View {
    let trip: Trip
    let travelers: [Person]

    @Environment(AppModel.self) private var appModel

    /// "You" for the signed-in user rather than their own name — reads naturally as "You and
    /// Lucas are going to Singapore" instead of the generic "Sarah & Lucas".
    private var travelerNames: String {
        let others = travelers.filter { $0.id != appModel.currentUser.id }.map(\.name)
        guard travelers.contains(where: { $0.id == appModel.currentUser.id }) else {
            return others.joined(separator: " and ")
        }
        return others.isEmpty ? "You" : "You and \(others.joined(separator: " and "))"
    }

    private var summaryLine: String {
        if let notes = trip.notes, !notes.isEmpty { return notes }
        let verb = travelers.count > 1 || travelers.first?.id == appModel.currentUser.id ? "are" : "is"
        return "\(travelerNames) \(verb) going to \(trip.destination.city)"
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
        HStack(spacing: Theme.Spacing.md) {
            if travelers.count > 1 {
                // Smaller + tighter overlap than the solo avatar — two full-size (36pt) avatars
                // left too little width for the origin → destination row, which wrapped onto a
                // second line for longer city names.
                HStack(spacing: -14) {
                    ForEach(travelers) { person in
                        AvatarView(person: person, size: 28)
                            .overlay(Circle().stroke(Theme.cardBackground, lineWidth: 2))
                    }
                }
            } else {
                AvatarView(person: travelers[0], size: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
                    // `summaryLine` falls back to `trip.notes` verbatim when set — that's
                    // free-form, unbounded user text, so this needs its own cap independent of
                    // the city row below (a long note shouldn't grow this fixed-style row).
                    .lineLimit(1)
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
                    Text(trip.departureDate, format: .dateTime.day().month(.abbreviated).year())
                    if let flight = trip.mostRelevantFlight {
                        Text(trip.flights.count > 1 ? "· \(flight.flightNumber) +\(trip.flights.count - 1)" : "· \(flight.flightNumber)")
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
