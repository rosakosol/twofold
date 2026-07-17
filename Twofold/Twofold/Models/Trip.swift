//
//  Trip.swift
//  Twofold
//

import Foundation

struct Trip: Identifiable, Hashable {
    let id: UUID
    var travelerID: Person.ID
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
        travelerID: Person.ID,
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
        self.travelerID = travelerID
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
        return flight.status.isActivelyTracked
    }
}
