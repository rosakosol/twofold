//
//  NextReunionCard.swift
//  Twofold
//
//  Home's countdown to the next trip, or the news that it is under way.
//

import SwiftUI

/// The card above the fold: a countdown to the next trip, or — once one is under way — the fact
/// that it is.
///
/// The under-way case used to be unreachable here. `upcomingTrips` includes active trips, but
/// `Trip.isActive` only returned true while an attached flight was in the air, so a trip with
/// no tracked flight counted as past the moment it began and never reached this card. Once
/// that was fixed, the card started showing in-progress trips and its copy did not fit them:
/// it counts down to `departureDate`, which is behind you mid-trip, so a `max(0, …)` clamp
/// pinned the count at zero and announced "Next reunion — Today" on day four of a visit.
///
/// The clamp is gone with it. `upcomingTrips` is `isUpcoming || isActive`, and `isUpcoming` is
/// `departureDate > .now`, so the only trips that now reach the countdown have a departure
/// strictly ahead of them and `daysUntil` — which counts calendar days — cannot go negative.
/// The sibling call sites in TripRowView, TripsCarouselCards and RelationshipMilestoneStats
/// keep theirs: those are reached by past trips too.
///
/// Deliberately not a countdown to the end. The remaining days are knowable — `arrivalDate` is
/// right there — but putting a timer on a visit turns the good half of a long-distance
/// relationship into a countdown to the goodbye.
struct NextReunionCard: View {
    @Environment(AppModel.self) private var appModel

    let trip: Trip

    var body: some View {
        let daysToGo = TimeMath.daysUntil(trip.departureDate)
        return SectionCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.isActive ? "Right now" : "Next reunion")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Text(trip.isActive ? "Together 💛" : (daysToGo == 0 ? "Today 💛" : "\(daysToGo) days to go"))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Image(systemName: "heart.fill")
                    .foregroundStyle(Theme.coral)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Past tense once they have gone. "Max flies to you" is a promise, and reading
                    // it on day four of the visit makes the app look like it has not noticed.
                    Text(tripSubtitle(trip))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                    let route = trip.routeEndpoints
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(route.origin)
                        Image(systemName: "arrow.right")
                        Text(route.destination)
                    }
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                    if let flight = trip.mostRelevantFlight {
                        Text("\(trip.departureDate, format: .dateTime.day().month(.abbreviated)) · \(flight.flightNumber)")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                ZStack {
                    Circle().fill(Theme.accentFill)
                    Image(systemName: "airplane")
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
            }
        }
    }

    /// Joins the resolvable names for a trip's travelers ("Alex" / "Alex & You") — falls back to
    /// `appModel.partner.name` for the (common) case of a single unresolvable/placeholder id,
    /// same fallback the old single-`travelerID` code used.
    private func travelerNames(_ ids: [Person.ID]) -> String {
        let names = ids.compactMap { appModel.couple.partner($0)?.name }
        guard !names.isEmpty else { return appModel.partner.name }
        return names.joined(separator: " & ")
    }

    /// Who is going where, in the tense that matches whether it has happened yet.
    ///
    /// `.solo` names the traveller because only one of them is moving and which one matters. The
    /// other categories do not: both are already "your trip together", and naming a traveller on a
    /// trip they are taking jointly would read as though the other were being left behind.
    private func tripSubtitle(_ trip: Trip) -> String {
        guard trip.category == .solo else {
            return trip.isActive ? "You're together now" : "Your trip together"
        }
        let names = travelerNames(trip.travelerIDs)
        let plural = trip.travelerIDs.count > 1
        if trip.isActive {
            return plural ? "\(names) are with you" : "\(names) is with you"
        }
        return plural ? "\(names) fly to you" : "\(names) flies to you"
    }
}
