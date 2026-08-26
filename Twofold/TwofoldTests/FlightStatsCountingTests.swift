//
//  FlightStatsCountingTests.swift
//  TwofoldTests
//
//  The Passport's "total airlines / airports / routes" headline numbers are counts of *distinct*
//  things, so what matters is the key each flight is reduced to. Both keys used to be derived from
//  display strings, which split one real thing into two (or merged several into one) in ways that
//  only show up once real flight data is messy.
//

import Testing
import Foundation
@testable import Twofold

struct FlightStatsCountingTests {

    private func airport(iata: String? = nil, icao: String? = nil, city: String? = nil, country: String? = nil) -> FlightAirport {
        var a = FlightAirport()
        a.iata = iata; a.icao = icao; a.city = city; a.country = country
        return a
    }

    private func flight(
        number: String,
        marketing: String? = nil,
        airlineCode: String? = nil,
        from: FlightAirport,
        to: FlightAirport
    ) -> Flight {
        Flight(
            flightNumberIATA: number,
            marketingFlightNumber: marketing,
            airlineCode: airlineCode,
            origin: from,
            destination: to,
            status: .scheduled
        )
    }

    private var couple: Couple { MockData.couple }

    private let mel = "MEL", sin = "SIN", lhr = "LHR"

    // MARK: - Airlines

    /// The reported case: five flights across three airlines counted as four.
    ///
    /// One of the three was flown twice, once on a codeshare. `flightNumber` returns the
    /// *marketing* number when there is one, so scraping its letters gave "QF" for that leg and
    /// "EK" for the other — the same operating airline, counted twice.
    @Test func codeshareDoesNotSplitOneAirlineIntoTwo() {
        let a = airport(iata: mel), b = airport(iata: sin), c = airport(iata: lhr)
        let flights = [
            flight(number: "EK405", airlineCode: "EK", from: a, to: b),
            // Same airline, sold under Qantas' number.
            flight(number: "EK406", marketing: "QF8406", airlineCode: "EK", from: b, to: a),
            flight(number: "SQ218", airlineCode: "SQ", from: a, to: b),
            flight(number: "SQ317", airlineCode: "SQ", from: b, to: c),
            flight(number: "BA15", airlineCode: "BA", from: c, to: b),
        ]
        let stats = FlightStats(flights: flights, couple: couple)
        #expect(stats.flightCount == 5)
        #expect(stats.airlines.count == 3, "expected EK/SQ/BA, got \(stats.airlines.map(\.name))")
        #expect(Set(stats.airlines.map(\.name)) == ["EK", "SQ", "BA"])
    }

    /// Falls back to the flight number for flights added before `airlineCode` was populated.
    @Test func airlineFallsBackToTheFlightNumberWhenNoCodeIsStored() {
        let a = airport(iata: mel), b = airport(iata: sin)
        let stats = FlightStats(flights: [flight(number: "QF35", from: a, to: b)], couple: couple)
        #expect(stats.airlines.map(\.name) == ["QF"])
    }

    /// A number that starts with a digit ("3K201", Jetstar Asia) yields no prefix, and with no
    /// stored code there's nothing to count — better than inventing an empty-named airline.
    @Test func unidentifiableAirlineIsNotCounted() {
        let a = airport(iata: mel), b = airport(iata: sin)
        let stats = FlightStats(flights: [flight(number: "3K201", from: a, to: b)], couple: couple)
        #expect(stats.airlines.isEmpty)
    }

    // MARK: - Airports

    /// `displayCode` falls back through `city`, so the same airport arriving with a city on one
    /// flight and an IATA code on another used to count as two places visited.
    @Test func sameAirportKnownByCodeAndByCityCountsOnce() {
        let byCode = airport(iata: mel)
        let byCityOnly = airport(city: "Melbourne")
        let sinAirport = airport(iata: sin)
        let flights = [
            flight(number: "SQ218", airlineCode: "SQ", from: byCode, to: sinAirport),
            flight(number: "SQ217", airlineCode: "SQ", from: sinAirport, to: byCityOnly),
        ]
        let stats = FlightStats(flights: flights, couple: couple)
        // MEL (once, from the coded leg) + SIN. The city-only end contributes nothing rather than
        // a second "Melbourne" airport.
        #expect(Set(stats.airports.map(\.name)) == ["MEL", "SIN"])
    }

    /// An airport with nothing resolved used to become a literal "—", which then ranked as a real
    /// airport — and every unresolved airport across every flight piled into that same one.
    @Test func unresolvedAirportsAreNotCountedAsAPlace() {
        let unknown = airport()
        let stats = FlightStats(
            flights: [flight(number: "SQ218", airlineCode: "SQ", from: airport(iata: mel), to: unknown)],
            couple: couple
        )
        #expect(stats.airports.map(\.name) == ["MEL"])
        #expect(!stats.airports.contains { $0.name == "—" })
    }

    // MARK: - Routes

    @Test func routesAreDirectionAgnostic() {
        let a = airport(iata: mel), b = airport(iata: sin)
        let flights = [
            flight(number: "SQ218", airlineCode: "SQ", from: a, to: b),
            flight(number: "SQ217", airlineCode: "SQ", from: b, to: a),
        ]
        let stats = FlightStats(flights: flights, couple: couple)
        #expect(stats.routes.count == 1)
        #expect(stats.routes.first?.count == 2)
    }

    /// A flight with an unidentifiable end contributes no route, rather than a half-named one that
    /// every other such flight would also collapse into.
    @Test func routeWithAnUnresolvedEndIsNotCounted() {
        let flights = [
            flight(number: "SQ218", airlineCode: "SQ", from: airport(iata: mel), to: airport()),
            flight(number: "BA15", airlineCode: "BA", from: airport(iata: lhr), to: airport()),
        ]
        let stats = FlightStats(flights: flights, couple: couple)
        #expect(stats.routes.isEmpty)
    }
}
