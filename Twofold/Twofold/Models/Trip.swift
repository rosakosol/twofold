//
//  Trip.swift
//  Twofold
//

import Foundation

enum TripCategory: String, CaseIterable, Hashable {
    case seeingEachOther = "To see each other"
    case together = "Together"
    case personal = "Personal"

    var shortLabel: String {
        switch self {
        case .seeingEachOther: "Reunion"
        case .together: "Together"
        case .personal: "Personal"
        }
    }
}

struct Trip: Identifiable, Hashable {
    let id: UUID
    var travelerID: Person.ID
    var origin: Place
    var destination: Place
    var departureDate: Date
    var arrivalDate: Date
    var category: TripCategory
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
        category: TripCategory,
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
        self.category = category
        self.distanceKm = distanceKm
        self.flight = flight
        self.notes = notes
    }

    var isUpcoming: Bool {
        departureDate > .now
    }

    var isActive: Bool {
        guard let flight else { return false }
        return departureDate <= .now && [.departed, .inAir, .landingSoon].contains(flight.status)
    }
}
