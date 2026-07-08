//
//  AppModel.swift
//  Twofold
//
//  In-memory root store standing in for a real backend/persistence layer.
//

import Foundation
import Observation

@Observable
final class AppModel {
    var hasCouple: Bool = false
    var couple: Couple = MockData.couple
    var trips: [Trip] = MockData.trips
    var memories: [Memory] = MockData.memories
    var stats: MockData.RelationshipStats = MockData.stats
    var nextReunionDaysToGo: Int = MockData.nextReunionDaysToGo

    /// Whether the partner has actually joined. There's no backend yet, so this is
    /// set locally the moment a code is shared/entered rather than confirmed by acceptance.
    var partnerConnected: Bool = false
    var inviteCode: String?

    var currentUser: Person { couple.partnerA }
    var partner: Person { couple.partnerB }

    var needsPartnerInvite: Bool { !partnerConnected }
    var needsFirstTrip: Bool { trips.isEmpty }
    var needsFirstFlight: Bool { !trips.contains { $0.flight != nil } }
    var needsHomeCities: Bool { couple.partnerA.homeCity == nil || couple.partnerB.homeCity == nil }

    var activeTrip: Trip? {
        trips.first { $0.isActive }
    }

    var upcomingTrips: [Trip] {
        trips.filter { $0.isUpcoming || $0.isActive }.sorted { $0.departureDate < $1.departureDate }
    }

    var pastTrips: [Trip] {
        trips.filter { !$0.isUpcoming && !$0.isActive }.sorted { $0.departureDate > $1.departureDate }
    }

    func memories(in place: Place) -> [Memory] {
        memories.filter { $0.place.id == place.id }
    }

    var citiesWithMemories: [Place] {
        var seen = Set<UUID>()
        return memories.compactMap { memory in
            guard !seen.contains(memory.place.id) else { return nil }
            seen.insert(memory.place.id)
            return memory.place
        }
    }

    /// Builds the real couple/trip/stats state from everything collected during onboarding
    /// and lands the user on the home screen.
    func completeOnboarding(_ onboarding: OnboardingModel) {
        let me = Person(
            name: onboarding.firstName.isEmpty ? "You" : onboarding.firstName,
            homeCity: onboarding.homeCity,
            accentColor: Person.palette[1]
        )
        let partnerName = onboarding.isPartnerConnected ? (onboarding.inviterName ?? "Partner") : "Partner"
        let partnerPerson = Person(name: partnerName, homeCity: nil, accentColor: Person.palette[0])

        couple = Couple(partnerA: me, partnerB: partnerPerson, startedDatingOn: .now)
        trips = onboarding.draftedTrip.map { [$0] } ?? []
        memories = []

        let totalDistance = trips.reduce(0) { $0 + $1.distanceKm }
        stats = MockData.RelationshipStats(
            totalDistanceKm: totalDistance,
            tripCount: trips.count,
            flightCount: trips.contains { $0.flight != nil } ? 1 : 0,
            countryCount: Set(trips.flatMap { [$0.origin.country, $0.destination.country] }).count,
            daysTogether: 0,
            earthMultiple: totalDistance / Geo.earthCircumferenceKm
        )

        partnerConnected = onboarding.isPartnerConnected
        inviteCode = onboarding.inviteCode
        hasCouple = true
    }

    @discardableResult
    func addTrip(origin: Place, destination: Place, departureDate: Date, arrivalDate: Date, traveler: TripTraveler, flightNumber: String?) -> Trip {
        let travelerID = traveler == .partner ? partner.id : currentUser.id
        let category: TripCategory = traveler == .both ? .together : .seeingEachOther
        let distance = Geo.distanceKm(origin.coordinate, destination.coordinate)

        var trip = Trip(
            travelerID: travelerID,
            origin: origin,
            destination: destination,
            departureDate: departureDate,
            arrivalDate: arrivalDate,
            category: category,
            distanceKm: distance
        )

        if let flightNumber, !flightNumber.isEmpty {
            trip.flight = Flight(
                flightNumber: flightNumber,
                origin: origin,
                destination: destination,
                status: .scheduled,
                scheduledDeparture: departureDate,
                scheduledArrival: arrivalDate,
                progress: 0,
                timeline: []
            )
        }

        trips.append(trip)
        return trip
    }

    func addFlight(to tripID: Trip.ID, flightNumber: String) {
        guard let index = trips.firstIndex(where: { $0.id == tripID }) else { return }
        let trip = trips[index]
        trips[index].flight = Flight(
            flightNumber: flightNumber,
            origin: trip.origin,
            destination: trip.destination,
            status: .scheduled,
            scheduledDeparture: trip.departureDate,
            scheduledArrival: trip.arrivalDate,
            progress: 0,
            timeline: []
        )
    }

    func setHomeCity(for personID: Person.ID, city: Place) {
        if couple.partnerA.id == personID {
            couple.partnerA.homeCity = city
        } else if couple.partnerB.id == personID {
            couple.partnerB.homeCity = city
        }
    }
}
