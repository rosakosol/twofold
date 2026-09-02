//
//  TripStatsTests.swift
//  TwofoldTests
//
//  The numbers behind All Trip Stats. A stats screen fails quietly — a wrong figure is still a
//  plausible figure — so the counting and the ranked lists are pinned here rather than eyeballed.
//

import Testing
import Foundation
@testable import Twofold

struct TripStatsTests {

    private let me = Person(name: "Alex", accentColor: Person.palette[0])
    private let partner = Person(name: "Sam", accentColor: Person.palette[1])

    private func place(_ city: String, country: String, lat: Double = 0, lon: Double = 0) -> Place {
        Place(id: UUID(), city: city, country: country, iataCode: nil, latitude: lat, longitude: lon)
    }

    private func trip(
        to destination: Place,
        from origin: Place? = nil,
        category: TripCategory,
        travelers: [Person.ID],
        departsInDays: Double = -30,
        lasting days: Double = 7
    ) -> Trip {
        let departure = Date.now.addingTimeInterval(departsInDays * 86_400)
        return Trip(
            travelerIDs: travelers,
            origin: origin ?? place("Melbourne", country: "Australia", lat: -37.8, lon: 144.9),
            destination: destination,
            departureDate: departure,
            arrivalDate: departure.addingTimeInterval(days * 86_400),
            category: category,
            distanceKm: 1000
        )
    }

    // MARK: - Counting

    @Test("each category is counted separately, and they add up to the total")
    func categoriesAddUp() {
        let rome = place("Rome", country: "Italy")
        let stats = TripStats(trips: [
            trip(to: rome, category: .reunion, travelers: [me.id]),
            trip(to: rome, category: .reunion, travelers: [partner.id]),
            trip(to: rome, category: .together, travelers: [me.id, partner.id]),
            trip(to: rome, category: .solo, travelers: [me.id]),
        ])
        #expect(stats.totalTrips == 4)
        #expect(stats.reunionCount == 2)
        #expect(stats.togetherCount == 1)
        #expect(stats.soloCount == 1)
        #expect(stats.reunionCount + stats.togetherCount + stats.soloCount == stats.totalTrips)
    }

    @Test("upcoming and taken split the total between them")
    func upcomingAndPastSplitTheTotal() {
        let rome = place("Rome", country: "Italy")
        let stats = TripStats(trips: [
            trip(to: rome, category: .together, travelers: [me.id], departsInDays: -60),
            trip(to: rome, category: .together, travelers: [me.id], departsInDays: 30),
            trip(to: rome, category: .together, travelers: [me.id], departsInDays: 90),
        ])
        #expect(stats.upcomingCount == 2)
        #expect(stats.pastCount == 1)
        #expect(stats.upcomingCount + stats.pastCount == stats.totalTrips)
    }

    // MARK: - Ranked lists

    /// The same city visited repeatedly is one destination, counted — the distinction the flight
    /// screen's headline numbers got wrong by being captioned "total".
    @Test("destinations are distinct places with a visit count each")
    func destinationsAreRanked() {
        let stats = TripStats(trips: [
            trip(to: place("Rome", country: "Italy"), category: .together, travelers: [me.id]),
            trip(to: place("Rome", country: "Italy"), category: .reunion, travelers: [me.id]),
            trip(to: place("Tokyo", country: "Japan"), category: .solo, travelers: [me.id]),
        ])
        #expect(stats.destinations.count == 2, "Rome and Tokyo, from three trips")
        #expect(stats.destinations.first?.name == "Rome")
        #expect(stats.destinations.first?.count == 2)
        #expect(stats.topDestination?.name == "Rome", "the summary card's single figure is the same list's first")
    }

    @Test("countries come from where the trip went, not where it started")
    func countriesAreDestinations() {
        let stats = TripStats(trips: [
            trip(to: place("Rome", country: "Italy"), category: .together, travelers: [me.id]),
            trip(to: place("Milan", country: "Italy"), category: .together, travelers: [me.id]),
            trip(to: place("Tokyo", country: "Japan"), category: .solo, travelers: [me.id]),
        ])
        #expect(stats.countries.map(\.name) == ["Italy", "Japan"])
        #expect(stats.countries.first?.count == 2)
        #expect(!stats.countries.contains { $0.name == "Australia" }, "the origin isn't somewhere the trip went")
    }

    /// A blank country would rank as its own entry, and every trip missing one would pile into it.
    @Test("a trip with no country recorded doesn't become a country")
    func blankCountriesAreSkipped() {
        let stats = TripStats(trips: [
            trip(to: place("Rome", country: "Italy"), category: .together, travelers: [me.id]),
            trip(to: place("Somewhere", country: "  "), category: .solo, travelers: [me.id]),
        ])
        #expect(stats.countries.map(\.name) == ["Italy"])
    }

    // MARK: - Durations

    @Test("averages divide by the number of trips, and survive having none")
    func averages() {
        let rome = place("Rome", country: "Italy")
        let stats = TripStats(trips: [
            trip(to: rome, category: .together, travelers: [me.id], lasting: 4),
            trip(to: rome, category: .together, travelers: [me.id], lasting: 10),
        ])
        #expect(stats.totalDays == 14)
        #expect(stats.averageDays == 7)
        #expect(TripStats(trips: []).averageDays == 0, "no trips must not divide by zero")
        #expect(TripStats(trips: []).averageDistanceKm == 0)
    }

    @Test("longest and shortest are the real extremes")
    func longestAndShortest() {
        let rome = place("Rome", country: "Italy")
        let tokyo = place("Tokyo", country: "Japan")
        let stats = TripStats(trips: [
            trip(to: rome, category: .together, travelers: [me.id], lasting: 3),
            trip(to: tokyo, category: .together, travelers: [me.id], lasting: 21),
        ])
        #expect(stats.longestTrip?.destination.city == "Tokyo")
        #expect(stats.shortestTrip?.destination.city == "Rome")
    }

    @Test("nothing in, zeroes out")
    func emptyIsSafe() {
        let stats = TripStats(trips: [])
        #expect(stats.totalTrips == 0)
        #expect(stats.destinations.isEmpty)
        #expect(stats.countries.isEmpty)
        #expect(stats.topDestination == nil)
        #expect(stats.longestTrip == nil)
    }
}
