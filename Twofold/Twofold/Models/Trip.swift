//
//  Trip.swift
//  Twofold
//

import Foundation

struct Trip: Identifiable, Hashable {
    let id: UUID
    /// 0, 1, or 2 of the couple's members — mirrors `Flight.travelerIDs`. Almost always 1, but
    /// both partners travelling together (e.g. a joint trip back home) is a real case the old
    /// scalar `travelerID` couldn't represent at all.
    var travelerIDs: [Person.ID]
    var origin: Place
    var destination: Place
    var departureDate: Date
    var arrivalDate: Date
    /// Replaces the old three-way "reason for travel" (Reunion/Together/Personal) category —
    /// simplified to the one distinction that actually mattered for how a trip reads elsewhere
    /// in the app (the reunion card, trip badges): is this trip about seeing your partner, or
    /// not.
    var isReunionTrip: Bool
    var distanceKm: Double
    var flight: Flight?
    var notes: String?

    init(
        id: UUID = UUID(),
        travelerIDs: [Person.ID],
        origin: Place,
        destination: Place,
        departureDate: Date,
        arrivalDate: Date,
        isReunionTrip: Bool,
        distanceKm: Double,
        flight: Flight? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.travelerIDs = travelerIDs
        self.origin = origin
        self.destination = destination
        self.departureDate = departureDate
        self.arrivalDate = arrivalDate
        self.isReunionTrip = isReunionTrip
        self.distanceKm = distanceKm
        self.flight = flight
        self.notes = notes
    }

    var isUpcoming: Bool {
        departureDate > .now
    }

    var isActive: Bool {
        guard let flight else { return false }
        return flight.isCurrentlyRelevant
    }
}
